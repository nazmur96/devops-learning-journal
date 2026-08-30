#!/usr/bin/env bash
# Provision a Fedora or Debian-family VM as a developer workspace.
#
# Usage:
#   sudo ./01-idempotent-workspace-provisioner.sh [username]
#
# The username is selected in this order:
#   1. First positional argument
#   2. PROVISION_USER environment variable
#   3. SUDO_USER (the account that invoked sudo)
#   4. "developer"

set -Eeuo pipefail
# -E: ERR traps are inherited by functions.
# -e: exit when an unhandled command fails.
# -u: treat an unset variable as an error.
# -o pipefail: fail a pipeline when any command in it fails.

# Files created by this script start with owner-only write permissions. The
# developer login umask is configured separately below.
umask 027

readonly LOG_FILE="/var/log/provisioner.log"
readonly LOCK_FILE="/run/lock/idempotent-workspace-provisioner.lock"
readonly DEVELOPERS_GROUP="developers"
readonly MAX_INSTALL_ATTEMPTS=3

CHANGES=0
LOG_FILE_CHANGED=0
OS_FAMILY=""
OS_ID=""
TARGET_USER=""
MISSING_PACKAGES=()
TEMP_FILES=()

usage() {
    cat <<'USAGE'
Usage: sudo ./01-idempotent-workspace-provisioner.sh [username]

Provision a Fedora or Debian-family VM as a developer workspace.
The optional username identifies the account to create or configure.
USAGE
}

early_error() {
    # Used before the root-owned log file is available.
    printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&2
}

log() {
    local level=$1
    shift
    printf '[%s] [%s] %s\n' \
        "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$level" "$*" \
        | tee -a "$LOG_FILE"
}

die() {
    log ERROR "$*"
    exit 1
}

mark_changed() {
    CHANGES=$((CHANGES + 1))
    log CHANGED "$*"
}

cleanup() {
    local temporary_file

    for temporary_file in "${TEMP_FILES[@]}"; do
        if [[ -e "$temporary_file" || -L "$temporary_file" ]]; then
            rm -f -- "$temporary_file"
        fi
    done
}

on_error() {
    local status=$1
    local line=$2

    trap - ERR
    log ERROR "Unexpected failure near line ${line} (exit status ${status})."
    exit "$status"
}

contains_word() {
    local words=$1
    local sought=$2
    [[ " $words " == *" $sought "* ]]
}

validate_username() {
    local username=$1

    # This conservative subset works with useradd and prevents usernames from
    # being interpreted as command options. Linux commonly limits names to 32
    # characters; '$' is intentionally excluded because this creates a person.
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        early_error "Invalid username '${username}'. Use 1-32 lowercase letters, digits, underscores, or hyphens; the first character must be a letter or underscore."
        exit 2
    fi

    if [[ "$username" == "root" ]]; then
        early_error "Refusing to configure root as the developer account."
        exit 2
    fi
}

select_target_user() {
    if (( $# > 1 )); then
        usage >&2
        exit 2
    fi

    if (( $# == 1 )); then
        TARGET_USER=$1
    elif [[ -n "${PROVISION_USER:-}" ]]; then
        TARGET_USER=$PROVISION_USER
    elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        TARGET_USER=$SUDO_USER
    else
        TARGET_USER="developer"
    fi

    validate_username "$TARGET_USER"
}

detect_os() {
    local os_release_file=""
    local detected_family=""
    ID=""
    ID_LIKE=""

    if [[ -r /etc/os-release ]]; then
        os_release_file="/etc/os-release"
    elif [[ -r /usr/lib/os-release ]]; then
        os_release_file="/usr/lib/os-release"
    else
        early_error "Cannot detect the operating system: no os-release file was found."
        exit 1
    fi

    # os-release is a root-owned shell-compatible data file. ShellCheck cannot
    # follow a runtime-selected path, so SC1090 is disabled for this one source.
    # shellcheck disable=SC1090
    source "$os_release_file"

    OS_ID=${ID,,}
    case "$OS_ID" in
        fedora)
            detected_family="fedora"
            ;;
        debian | ubuntu | linuxmint | pop)
            detected_family="debian"
            ;;
        *)
            if contains_word "${ID_LIKE:-}" "debian"; then
                detected_family="debian"
            elif contains_word "${ID_LIKE:-}" "rhel" \
                || contains_word "${ID_LIKE:-}" "centos" \
                || contains_word "${ID_LIKE:-}" "fedora"; then
                detected_family="unsupported-rpm"
            else
                detected_family="unsupported"
            fi
            ;;
    esac

    case "$detected_family" in
        fedora | debian)
            OS_FAMILY=$detected_family
            ;;
        unsupported-rpm)
            early_error "Detected '${OS_ID}' in the RHEL/Fedora family, but only Fedora is supported. Docker Engine repository setup differs on RHEL derivatives, so no changes were made."
            exit 1
            ;;
        *)
            early_error "Unsupported operating system '${OS_ID:-unknown}'. No changes were made."
            exit 1
            ;;
    esac
}

setup_log_file() {
    local current_metadata=""

    if [[ -L "$LOG_FILE" ]]; then
        early_error "Refusing to use symlinked log file '${LOG_FILE}'."
        exit 1
    fi

    if [[ -e "$LOG_FILE" && ! -f "$LOG_FILE" ]]; then
        early_error "Log path '${LOG_FILE}' exists but is not a regular file."
        exit 1
    fi

    if [[ ! -e "$LOG_FILE" ]]; then
        install -o root -g root -m 0600 /dev/null "$LOG_FILE"
        LOG_FILE_CHANGED=1
    else
        current_metadata=$(stat -c '%a:%u:%g' -- "$LOG_FILE")
        if [[ "$current_metadata" != "600:0:0" ]]; then
            chown root:root "$LOG_FILE"
            chmod 0600 "$LOG_FILE"
            LOG_FILE_CHANGED=1
        fi
    fi
}

require_command() {
    local command_name=$1
    command -v "$command_name" >/dev/null 2>&1 \
        || die "Required command '${command_name}' is unavailable."
}

preflight_checks() {
    local command_name
    local common_commands=(
        chmod chown cmp date flock getent groupadd id install mktemp mv
        rm stat systemctl tee useradd usermod
    )

    for command_name in "${common_commands[@]}"; do
        require_command "$command_name"
    done

    case "$OS_FAMILY" in
        fedora)
            require_command dnf
            require_command rpm
            ;;
        debian)
            require_command apt-get
            require_command dpkg-query
            ;;
    esac

    if [[ ! -d /run/systemd/system ]]; then
        die "systemd is not running. This provisioner targets full VMs and will not partially configure a container or WSL environment."
    fi
}

run_logged() {
    local description=$1
    shift

    local output_file=""
    local output_line=""
    local status=0

    output_file=$(mktemp /tmp/provisioner-command.XXXXXX)
    TEMP_FILES+=("$output_file")

    log ACTION "$description"
    if "$@" >"$output_file" 2>&1; then
        status=0
    else
        status=$?
    fi

    while IFS= read -r output_line || [[ -n "$output_line" ]]; do
        log OUTPUT "$output_line"
    done <"$output_file"

    rm -f -- "$output_file"

    if (( status != 0 )); then
        log ERROR "${description} failed with exit status ${status}."
    fi

    return "$status"
}

package_installed() {
    local package_name=$1

    case "$OS_FAMILY" in
        fedora)
            rpm -q --quiet "$package_name"
            ;;
        debian)
            [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$package_name" 2>/dev/null || true)" == "ii " ]]
            ;;
    esac
}

docker_engine_present() {
    command -v docker >/dev/null 2>&1 \
        && systemctl cat docker.service >/dev/null 2>&1
}

collect_missing_packages() {
    local package_name
    local docker_package=""
    local required_packages=()

    case "$OS_FAMILY" in
        fedora)
            # Fedora has no package literally named build-essential. These three
            # packages provide the equivalent compiler/make toolchain.
            required_packages=(git curl gcc gcc-c++ make python3 jq sudo)
            docker_package="moby-engine"
            ;;
        debian)
            required_packages=(git curl build-essential python3 jq sudo)
            docker_package="docker.io"
            ;;
    esac

    MISSING_PACKAGES=()
    for package_name in "${required_packages[@]}"; do
        if package_installed "$package_name"; then
            log NOCHANGE "Package '${package_name}' is already installed."
        else
            MISSING_PACKAGES+=("$package_name")
        fi
    done

    # An administrator may already have installed Docker CE from Docker's own
    # repository. Checking the executable and service avoids replacing it with a
    # conflicting distro package merely because the package name differs.
    if docker_engine_present; then
        log NOCHANGE "A Docker-compatible engine and docker.service are already present."
    else
        MISSING_PACKAGES+=("$docker_package")
    fi
}

install_packages_once() {
    case "$OS_FAMILY" in
        fedora)
            # --refresh avoids relying on stale repository metadata; -y answers
            # package-manager confirmation prompts non-interactively.
            dnf --refresh -y install "${MISSING_PACKAGES[@]}"
            ;;
        debian)
            # apt metadata must be refreshed separately. The explicit && is
            # important: this function is called from an if condition, where
            # Bash's errexit behavior is easy to misunderstand.
            apt-get update \
                && env DEBIAN_FRONTEND=noninteractive \
                    apt-get install -y --no-install-recommends \
                    "${MISSING_PACKAGES[@]}"
            ;;
    esac
}

install_missing_packages() {
    local attempt=0
    local delay=0
    local install_status=0
    local package_name

    collect_missing_packages
    if (( ${#MISSING_PACKAGES[@]} == 0 )); then
        log NOCHANGE "All required packages are already installed."
        return 0
    fi

    log INFO "Missing packages: ${MISSING_PACKAGES[*]}"

    for ((attempt = 1; attempt <= MAX_INSTALL_ATTEMPTS; attempt++)); do
        if run_logged \
            "Package installation attempt ${attempt}/${MAX_INSTALL_ATTEMPTS}" \
            install_packages_once; then
            install_status=0
            break
        else
            install_status=$?
        fi

        if (( attempt < MAX_INSTALL_ATTEMPTS )); then
            # Exponential backoff: two seconds after attempt 1, then four.
            delay=$((2 ** attempt))
            log WARN "Package installation failed; retrying in ${delay} seconds."
            sleep "$delay"
        fi
    done

    if (( install_status != 0 )); then
        die "Package installation failed after ${MAX_INSTALL_ATTEMPTS} attempts. Check repository/network details above and rerun the script."
    fi

    # Do not trust only the package manager's exit code; verify desired state.
    for package_name in "${MISSING_PACKAGES[@]}"; do
        if ! package_installed "$package_name"; then
            die "Package manager reported success, but '${package_name}' is not installed."
        fi
        mark_changed "Installed package '${package_name}'."
    done
}

ensure_group() {
    local group_name=$1

    if getent group "$group_name" >/dev/null; then
        log NOCHANGE "Group '${group_name}' already exists."
        return 0
    fi

    run_logged "Create group '${group_name}'" groupadd "$group_name"
    mark_changed "Created group '${group_name}'."
}

ensure_user() {
    local username=$1
    local primary_group_options=()

    if getent passwd "$username" >/dev/null; then
        log NOCHANGE "User '${username}' already exists; existing home and shell were preserved."
        return 0
    fi

    # Prefer a user-private primary group. If a same-named group already exists,
    # reuse it rather than letting useradd fail or choosing a surprising group.
    if getent group "$username" >/dev/null; then
        primary_group_options=(--gid "$username")
    else
        primary_group_options=(--user-group)
    fi

    run_logged \
        "Create user '${username}' with a home directory and Bash login shell" \
        useradd --create-home --shell /bin/bash \
        "${primary_group_options[@]}" "$username"
    mark_changed "Created user '${username}'."
    log WARN "The new account has no password or SSH key. Configure one deliberately before interactive login."
}

user_in_group() {
    local username=$1
    local group_name=$2
    local memberships=""

    memberships=$(id -nG "$username")
    [[ " $memberships " == *" $group_name "* ]]
}

ensure_user_in_group() {
    local username=$1
    local group_name=$2

    if user_in_group "$username" "$group_name"; then
        log NOCHANGE "User '${username}' is already in group '${group_name}'."
        return 0
    fi

    # -a means append. Omitting it would replace all supplementary groups, a
    # common and dangerous usermod mistake. -G selects supplementary groups.
    run_logged \
        "Add user '${username}' to supplementary group '${group_name}'" \
        usermod -a -G "$group_name" "$username"
    mark_changed "Added user '${username}' to group '${group_name}'."
}

validate_sudoers_file() {
    local candidate_file=$1
    visudo -cf "$candidate_file"
}

ensure_managed_file() {
    local path=$1
    local mode=$2
    local content=$3
    local validator=${4:-}
    local current_metadata=""
    local expected_metadata="${mode#0}:0:0"
    local temporary_file=""
    local validation_output=""

    if [[ -L "$path" ]]; then
        die "Refusing to replace symlinked managed path '${path}'."
    fi

    if [[ -e "$path" && ! -f "$path" ]]; then
        die "Managed path '${path}' exists but is not a regular file."
    fi

    temporary_file=$(mktemp "${path}.tmp.XXXXXX")
    TEMP_FILES+=("$temporary_file")
    printf '%s\n' "$content" >"$temporary_file"
    chown root:root "$temporary_file"
    chmod "$mode" "$temporary_file"

    if [[ -f "$path" ]]; then
        current_metadata=$(stat -c '%a:%u:%g' -- "$path")
        if cmp -s -- "$temporary_file" "$path" \
            && [[ "$current_metadata" == "$expected_metadata" ]]; then
            rm -f -- "$temporary_file"
            log NOCHANGE "Managed file '${path}' already has the required content and permissions."
            return 0
        fi
    fi

    if [[ -n "$validator" ]]; then
        if ! validation_output=$("$validator" "$temporary_file" 2>&1); then
            while IFS= read -r validation_line; do
                log ERROR "$validation_line"
            done <<<"$validation_output"
            die "Validation failed for candidate managed file '${path}'; the existing file was not changed."
        fi
    fi

    # The candidate is in the destination directory, so rename is atomic on the
    # same filesystem. Readers see either the old complete file or the new one.
    mv -f -- "$temporary_file" "$path"
    mark_changed "Installed or repaired managed file '${path}'."
}

configure_umask() {
    local umask_content=""

    umask_content=$(printf '%s\n' \
        '# Managed by 01-idempotent-workspace-provisioner.sh.' \
        "# Apply a private-by-default umask only to ${TARGET_USER}." \
        "if [ \"\$(id -un)\" = \"${TARGET_USER}\" ]; then" \
        '    umask 027' \
        'fi')

    ensure_managed_file \
        "/etc/profile.d/99-${TARGET_USER}-umask.sh" \
        0644 "$umask_content"
}

configure_sudoers() {
    local sudoers_content=""

    require_command visudo
    sudoers_content=$(printf '%s\n' \
        '# Managed by 01-idempotent-workspace-provisioner.sh.' \
        '%developers ALL=(ALL:ALL) ALL')

    # 0440 prevents ordinary users from modifying privilege policy. visudo -c
    # validates syntax before the candidate atomically replaces the destination.
    ensure_managed_file \
        "/etc/sudoers.d/90-${DEVELOPERS_GROUP}" \
        0440 "$sudoers_content" validate_sudoers_file
}

ensure_docker_service() {
    if systemctl is-enabled --quiet docker.service; then
        log NOCHANGE "docker.service is already enabled at boot."
    else
        run_logged "Enable docker.service at boot" \
            systemctl enable docker.service
        mark_changed "Enabled docker.service at boot."
    fi

    if systemctl is-active --quiet docker.service; then
        log NOCHANGE "docker.service is already running."
    else
        run_logged "Start docker.service" systemctl start docker.service
        mark_changed "Started docker.service."
    fi
}

main() {
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    select_target_user "$@"

    if (( EUID != 0 )); then
        early_error "Root privileges are required. Run with: sudo $0 ${TARGET_USER}"
        exit 1
    fi

    # Detection happens before any filesystem or package mutation.
    detect_os
    setup_log_file

    trap cleanup EXIT
    trap 'status=$?; on_error "$status" "$LINENO"' ERR

    log INFO "Starting developer workspace provisioning for '${TARGET_USER}' on '${OS_ID}' (${OS_FAMILY} family)."
    if (( LOG_FILE_CHANGED == 1 )); then
        mark_changed "Created or repaired '${LOG_FILE}' with root-only permissions."
    fi

    preflight_checks

    # flock prevents two provisioners from racing over package-manager locks,
    # users, or configuration files. The lock is released when fd 9 closes.
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        die "Another provisioner process holds '${LOCK_FILE}'. Wait for it to finish."
    fi

    install_missing_packages

    ensure_group "$DEVELOPERS_GROUP"
    ensure_group "docker"
    ensure_user "$TARGET_USER"
    ensure_user_in_group "$TARGET_USER" "$DEVELOPERS_GROUP"
    ensure_user_in_group "$TARGET_USER" "docker"

    configure_umask
    configure_sudoers
    ensure_docker_service

    log WARN "Membership in the docker group grants root-equivalent control of the host. It becomes visible to an existing login after logout/login."
    log INFO "Provisioning complete: ${CHANGES} managed-state change(s)."
}

main "$@"
