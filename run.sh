#!/bin/sh

set -e

URL=$WERCKER_RANCHER_UPGRADE_URL
ACCESS_KEY=$WERCKER_RANCHER_UPGRADE_ACCESS_KEY
SECRET=$WERCKER_RANCHER_UPGRADE_SECRET
SERVICE_ID=$WERCKER_RANCHER_UPGRADE_SERVICE_ID
IMAGE=$WERCKER_RANCHER_UPGRADE_IMAGE
TIMEOUT=${WERCKER_RANCHER_UPGRADE_TIMEOUT:-"60"}


get(){
  curl -s --user "$ACCESS_KEY:$SECRET" "$URL/v1/services/$SERVICE_ID"
}

upgrade(){
  info "---> Upgrading"

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
    service=$(get)
    state=$(echo $service | jq -r '.state')

    case $state in
      upgraded)
        info "---> Upgraded"
        finish_url=$(echo $service | jq -r '.actions.finishupgrade')
        curl -s --user "$ACCESS_KEY:$SECRET" -X POST "$finish_url" > /dev/null
        success "Finished"
        return
        ;;

      *)
        info "---> Waiting ($TIMEOUT) - $state"
        TIMEOUT=$((TIMEOUT - 1))
        sleep 1
        ;;
    esac
  done

  info "---> Upgrade timeout. Cancel upgrade"
  cancel_url=$(echo $service | jq -r '.actions.cancelupgrade')
  curl -s --user "$ACCESS_KEY:$SECRET" -X POST "$cancel_url" > /dev/null

  while true; do
    service=$(get)
    state=$(echo $service | jq -r '.state')

    case $state in
      canceling-upgrade)
        info "---> Canceling upgrade"
        sleep 1
        ;;

      *)
        fail "---> Upgrade cancelled"
        ;;
    esac
  done
}

main(){
  service=$(get)
  state=$(echo $service | jq -r '.state')

  case $state in
    active)
      upgrade
      ;;

    *)
      fail "---> Can't upgrade, service $SERVICE_ID is $state"
      ;;
  esac
}

main
