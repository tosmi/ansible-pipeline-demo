#!/bin/bash

set -eu -o pipefail

if [ "${PARAM_VERBOSE}" = "true" ] ; then
    set -x
fi

PATH=/bin:/usr/bin

CONTROLLER_BASE_URL=${CONTROLLER_BASE_URL:-}
CONTROLLER_TOKEN=${CONTROLLER_TOKEN:-}
CONTROLLER_JOB_ID=${CONTROLLER_JOB_ID:-}
CONTROLLER_JOB_NAME=${CONTROLLER_JOB_NAME:-}
CONTROLLER_JOB_ARGS=${CONTROLLER_JOB_ARGS:-}
CONTROLLER_WORKFLOW=${CONTROLLER_WORKFLOW:-}

if [ "${CONTROLLER_WORKFLOW}" == "yes" ]; then
    CONTROLLER_JOB_URL="workflow_job_templates"
else
    CONTROLLER_JOB_URL="job_templates"
fi

SLEEP=${SLEEP:-5}

RED="\e[31m"
YELLOW="\e[33m"
BOLD="\033[1m"
NC="\e[0m"

error() {
    local MESSAGE="$1"
    local DATE

    DATE=$(date "+%d/%b/%Y:%H:%M:%S %z")

    # shellcheck disable=SC3037
    echo -e "[${DATE}] ${RED}ERROR:${NC} $MESSAGE" >&2
    exit 1
}

info() {
    local MESSAGE="$1"
    local DATE

    DATE=$(date "+%d/%b/%Y:%H:%M:%S %z")

    # shellcheck disable=SC3037
    echo -e "[${DATE}] ${YELLOW}INFO:${NC} $MESSAGE" >&2

    return 0
}

run_job() {
    info "Using Ansible Controller at ${BOLD}${CONTROLLER_BASE_URL}${NC}"
    info "Triggering Job template ${BOLD}${CONTROLLER_JOB_NAME}${NC}"

    CONTROLLER_JOB_NAME_URI_ESCAPED=${CONTROLLER_JOB_NAME// /%20}

    JOB_URL=$(curl -qsk -H "Accept: application/json" -H "Authorization: Bearer $CONTROLLER_TOKEN" -X POST "${CONTROLLER_BASE_URL}/api/v2/${CONTROLLER_JOB_URL}/${CONTROLLER_JOB_NAME_URI_ESCAPED}/launch/" | /bin/jq -r .url)

    [ "$JOB_URL" = "" ] && error "Trigger job ${CONTROLLER_JOB_NAME} failed!"
    [ "$JOB_URL" = "null" ] && error "Trigger job ${CONTROLLER_JOB_NAME} failed!"

    info "Job successfully triggered!"
    info "Job URL is ${JOB_URL}"
    echo "$JOB_URL"
}

verify() {
    [ -z "$CONTROLLER_BASE_URL" ] && error "Environment variable ${BOLD}CONTROLLER_BASE_URL${NC} is not defined"
    [ -z "$CONTROLLER_TOKEN" ] && error "Environment variable ${BOLD}CONTROLLER_TOKEN${NC} is not defined"
    [ -z "$CONTROLLER_JOB_NAME" ] && error "Environment variable ${BOLD}CONTROLLER_JOB_NAME{NC} is not defined"

    return 0
}

wait_for_job() {
    local JOB_URL="$1"
    local JOB_STATE

    JOB_FULL_URL="${CONTROLLER_BASE_URL}${JOB_URL}"

    info "Waiting for job ${BOLD}$JOB_URL${NC} to finish..."
    while true; do
	JOB_STATE=$(curl -qsk -H "Accept: application/json" -H "Authorization: Bearer $CONTROLLER_TOKEN" -X GET "${JOB_FULL_URL}" | /bin/jq -r .status)

	case "$JOB_STATE" in
	    pending|waiting|running)
		info "Job ${BOLD}${JOB_URL}${NC} is in state ${BOLD}${JOB_STATE}${NC}..."
		;;
	    failed)
		error "Job ${BOLD}${JOB_URL}${NC} failed!"
		;;
	    canceled)
		error "Job ${BOLD}${JOB_URL}${NC} was canceled!"
		;;
	    successful)
		info "Job ${BOLD}$JOB_URL${NC} successfully finished"
		return 0
		;;
	    *)
		error "Unkown job status ${BOLD}${JOB_STATE}${NC} for job ${BOLD}${JOB_URL}${NC}!"
	esac

	sleep "${SLEEP}"
    done
}

get_tower_jobs_name_by_id() {
    local JOB_ID
    local JOB_NAME

    JOB_ID="$1"
    JOB_NAME=$(curl -qsk -H "Accept: application/json" -H "Authorization: Bearer $CONTROLLER_TOKEN" -X GET "${CONTROLLER_BASE_URL}/api/v2/${CONTROLLER_JOB_URL}/${JOB_ID}/" | /bin/jq -r .name)

    echo "${JOB_NAME}"
}

main() {
    info "Token                    : ${CONTROLLER_TOKEN}"
    info "Automation Controller URL: ${CONTROLLER_BASE_URL}"
    info "Template                 : ${CONTROLLER_JOB_NAME}"
    info "Template arguments       : ${CONTROLLER_JOB_ARGS}"

    if [ -n "$CONTROLLER_JOB_ID" ] && [ -z "$CONTROLLER_JOB_NAME" ]; then
	CONTROLLER_JOB_NAME=$(get_tower_jobs_name_by_id "$CONTROLLER_JOB_ID")
    fi

    # URL Escape the job name in case it contains blanks
    # CONTROLLER_JOB_NAME=$(echo "$CONTROLLER_JOB_NAME" | sed 's/ /%20/g')
    JOB_URL=$(run_job "$CONTROLLER_JOB_NAME")
    wait_for_job "$JOB_URL"
}

verify
main
