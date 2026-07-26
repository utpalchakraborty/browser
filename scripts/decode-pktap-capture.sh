#!/bin/sh

set -eu

usage() {
    echo "usage: $0 CAPTURE TCPDUMP_LOG PACKETS_OUTPUT READ_LOG" >&2
}

if [ "$#" -ne 4 ]; then
    usage
    exit 2
fi

capture_path=$1
tcpdump_log=$2
packets_output=$3
read_log=$4

for required_file in "$capture_path" "$tcpdump_log"; do
    if [ ! -f "$required_file" ]; then
        echo "Capture evidence is missing: $required_file" >&2
        exit 1
    fi
done

if /usr/sbin/tcpdump \
    -nn \
    -q \
    -K \
    -k NPDI \
    -r "$capture_path" \
    >"$packets_output" \
    2>"$read_log"
then
    /usr/bin/awk 'NF { count += 1 } END { print count + 0 }' \
        "$packets_output"
    exit 0
fi

# On macOS, tcpdump may leave a zero-byte pcapng when the pktap metadata filter
# accepts no packets. Accept that special case only after the live capture has
# exited successfully and its own summary reports zero captured packets and
# zero kernel drops. The caller separately enforces capture liveness, process
# identity, exit status, duration, and a positive attribution control.
listening_lines=$(
    /usr/bin/grep -Ec '^tcpdump: listening on pktap' "$tcpdump_log" || true
)
captured_lines=$(
    /usr/bin/grep -Ec '^0 packets captured$' "$tcpdump_log" || true
)
kernel_drop_lines=$(
    /usr/bin/grep -Ec '^0 packets dropped by kernel$' "$tcpdump_log" || true
)
received_lines=$(
    /usr/bin/grep -Ec '^[0-9]+ packets received by filter$' "$tcpdump_log" \
        || true
)
metadata_drop_lines=$(
    /usr/bin/grep -Ec '^[0-9]+ drops by metadata filter$' "$tcpdump_log" \
        || true
)

received_count=""
metadata_drop_count=""
if [ "$received_lines" -eq 1 ] && [ "$metadata_drop_lines" -eq 1 ]; then
    received_count=$(
        /usr/bin/sed -n \
            's/^\([0-9][0-9]*\) packets received by filter$/\1/p' \
            "$tcpdump_log"
    )
    metadata_drop_count=$(
        /usr/bin/sed -n \
            's/^\([0-9][0-9]*\) drops by metadata filter$/\1/p' \
            "$tcpdump_log"
    )
fi

if [ ! -s "$capture_path" ] \
    && [ ! -s "$packets_output" ] \
    && [ "$listening_lines" -eq 1 ] \
    && [ "$captured_lines" -eq 1 ] \
    && [ "$kernel_drop_lines" -eq 1 ] \
    && [ -n "$received_count" ] \
    && [ "$received_count" = "$metadata_drop_count" ]
then
    echo "Zero-byte pcapng accepted from completed zero-packet tcpdump summary." \
        >>"$read_log"
    echo 0
    exit 0
fi

echo "Unable to decode pktap capture: $capture_path" >&2
/usr/bin/sed -n '1,80p' "$read_log" >&2
exit 1
