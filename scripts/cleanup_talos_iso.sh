#!/bin/bash
set -e

VM_NAME="talos-cp-01"
VM_ID="71"
MACHINE_ID="93"
DRIVE_KEY="91"
API_URL="https://192.168.1.111/api/v4"
# Check for env vars
if [[ -z "$VERGEOS_USER" || -z "$VERGEOS_PASS" ]]; then
  echo "Error: VERGEOS_USER and VERGEOS_PASS must be set."
  exit 1
fi

AUTH="$VERGEOS_USER:$VERGEOS_PASS"

echo "Forcing power off for VM $VM_NAME ($VM_ID)..."
curl -s -k -u "$AUTH" -X POST "$API_URL/machines/$MACHINE_ID/kill_power"

echo "Waiting for VM to be fully offline..."
for i in {1..12}; do
  STATE=$(curl -s -k -u "$AUTH" "$API_URL/vms/$VM_ID" | jq -r '.powerstate')
  echo "Current powerstate: $STATE"
  if [[ "$STATE" == "false" || "$STATE" == "null" ]]; then
     # Check machine status as well
     MSTATE=$(curl -s -k -u "$AUTH" "$API_URL/machines/$MACHINE_ID" | jq -r '.powerstate')
     if [[ "$MSTATE" == "false" || "$MSTATE" == "null" ]]; then
       echo "VM is confirmed offline."
       break
     fi
  fi
  sleep 5
done

echo "Removing CD-ROM Drive (Key $DRIVE_KEY)..."
curl -s -k -u "$AUTH" -X DELETE "$API_URL/machine_drives/$DRIVE_KEY" | jq '.'

echo "Starting VM $VM_NAME..."
curl -s -k -u "$AUTH" -X PUT -d '{"powerstate":true}' "$API_URL/vms/$VM_ID"

echo "Cleanup complete!"
