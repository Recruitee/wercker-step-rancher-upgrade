#!/bin/sh

set -e

URL=$WERCKER_RANCHER_UPGRADE_URL
ACCESS_KEY=$WERCKER_RANCHER_UPGRADE_ACCESS_KEY
SECRET=$WERCKER_RANCHER_UPGRADE_SECRET
SERVICE_ID=$WERCKER_RANCHER_UPGRADE_SERVICE_ID
IMAGE=$WERCKER_RANCHER_UPGRADE_IMAGE
TIMEOUT=${WERCKER_RANCHER_UPGRADE_TIMEOUT:-"60"}

_get (){
  curl -s --user "$ACCESS_KEY:$SECRET" "$URL/v1/services/$SERVICE_ID"
}

service=$(_get)
state=$(echo $service | jq -r '.state')

case $state in
  active)
    echo "---> Upgrading" >&2

    up_url=$(echo $service | jq -r '.actions.upgrade')
    up_data=$(echo $service | jq -r --arg img "docker:$IMAGE" '
        .upgrade.inServiceStrategy
      | .launchConfig.imageUuid = $img
      | .startFirst = true
      | del(.previousSecondaryConfigs)
      | del(.previousSecondaryLaunchConfigs)
      | {inServiceStrategy: .}
    ')

    curl -s --user "$ACCESS_KEY:$SECRET" -X POST "$up_url" -H 'Content-Type: application/json' -d "$up_data" > /dev/null

    while [ "$TIMEOUT" -gt "0" ]; do
      service=$(_get)
      state=$(echo $service | jq -r '.state')

      case $state in
        upgraded)
          echo "---> Upgraded"
          finish_url=$(echo $service | jq -r '.actions.finishupgrade')
          curl -s --user "$ACCESS_KEY:$SECRET" -X POST "$finish_url" > /dev/null
          echo "---> Finished"
          exit 0
          ;;

        *)
          echo "---> Waiting ($TIMEOUT) - $state" >&2
          TIMEOUT=$((TIMEOUT - 1))
          sleep 1
          ;;
      esac
    done

    echo "---> Upgrade timeout. Cancel upgrade" >&2
    echo $service
    cancel_url=$(echo $service | jq -r '.actions.cancelupgrade')
    curl -s --user "$ACCESS_KEY:$SECRET" -X POST "$cancel_url" > /dev/null

    while true; do
      service=$(_get)
      state=$(echo $service | jq -r '.state')

      case $state in
        canceling-upgrade)
          echo "---> Canceling upgrade"
          sleep 1
          ;;

        *)
          exit 2
          ;;
      esac
    done
    ;;

  *)
    echo "---> ERROR: Can't upgrade, service $SERVICE_ID is $state"
    ;;
esac
