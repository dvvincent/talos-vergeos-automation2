#!/bin/bash
set -e

# Configuration: "VM_NAME:VM_ID:MACHINE_ID:DRIVE_KEY"
NODES=(
  "talos-cp-01:38:50:24"
  "talos-worker-01:71:93:81"
)

API_URL="https://192.168.1.111/api/v4"

# Check for env vars
if [[ -z "$VERGEOS_USER" || -z "$VERGEOS_PASS" ]]; then
  echo "Error: VERGEOS_USER and VERGEOS_PASS must be set."
  exit 1
fi

AUTH="$VERGEOS_USER:$VERGEOS_PASS"

for NODE in "${NODES[@]}"; do
  IFS=':' read -r VM_NAME VM_ID MACHINE_ID DRIVE_KEY <<< "$NODE"
  
  echo "Processing $VM_NAME (VM:$VM_ID, Machine:$MACHINE_ID, Drive:$DRIVE_KEY)..."

  # Check if drive exists first
  DRIVE_INFO=$(curl -s -k -u "$AUTH" "$API_URL/machine_drives/$DRIVE_KEY")
  IS_FOUND=$(echo "$DRIVE_INFO" | jq -r '."$key" // empty')
  
  if [[ -z "$IS_FOUND" ]]; then
    echo "  Drive $DRIVE_KEY not found. Skipping."
    continue
  fi

  echo "  Forcing power off via /vms/$VM_ID/kill..."
  # Using the pattern suggested by user: POST to/{id}/{action}
  curl -s -k -u "$AUTH" -X POST -d '{}' "$API_URL/vms/$VM_ID/kill" > /dev/null

  echo "  Waiting for VM to be fully offline..."
  for i in {1..30}; do
    STATE=$(curl -s -k -u "$AUTH" "$API_URL/vms/$VM_ID" | jq -r '.powerstate')
    if [[ "$STATE" == "false" || "$STATE" == "null" ]]; then
       MSTATE=$(curl -s -k -u "$AUTH" "$API_URL/machines/$MACHINE_ID" | jq -r '.powerstate')
       if [[ "$MSTATE" == "false" || "$MSTATE" == "null" ]]; then
         echo "  VM offline."
         break
       fi
    fi
    sleep 2
  done

  echo "  Delaying 10 seconds for deep offline state..."
  sleep 10

  echo "  Removing CD-ROM Drive ($DRIVE_KEY)..."
  DEL_RESP=$(curl -s -k -u "$AUTH" -X DELETE "$API_URL/machine_drives/$DRIVE_KEY")
  ERR_MSG=$(echo "$DEL_RESP" | jq -r 'if type == "array" then .[0].err // empty else .err // empty end')
  if [[ -z "$ERR_MSG" ]]; then
    echo "  Success: Drive removed."
  else
    echo "  Error removing drive: $ERR_MSG"
  fi

  echo "  Starting VM via /vms/$VM_ID/poweron..."
  curl -s -k -u "$AUTH" -X POST -d '{}' "$API_URL/vms/$VM_ID/poweron" > /dev/null
  echo "  VM Started."
  echo "-----------------------------------"
done

echo "Cluster ISO cleanup complete!"
