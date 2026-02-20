#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
SKILL_NAME="signature-map"
DEFAULT_REF="main"
DEFAULT_REPO="Xopoko/SignatureMap"
EXIT_USAGE=2
EXIT_RUNTIME=3
EXIT_PARTIAL=4

BEGIN_TAG="<!-- BEGIN signature-map managed -->"
END_TAG="<!-- END signature-map managed -->"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUBCOMMAND="install"
AGENT="auto"
SCOPE="global"
WITH_INSTRUCTIONS=1
KEEP_INSTRUCTIONS=0
FORCE=0
DRY_RUN=0
VERBOSE=0
PROJECT_ROOT=""
REPO="${DEFAULT_REPO}"
REF="${DEFAULT_REF}"
SOURCE_MODE="auto"
CODEX_HOME_OVERRIDE=""
CLAUDE_HOME_OVERRIDE=""
CODEX_LAYOUT="auto"

usage() {
  cat <<'USAGE'
Signature Map installer

Usage:
  ./install.sh [install|update|uninstall|doctor] [options]

Subcommands:
  install     Install skill (default)
  update      Reinstall/refresh skill (implies --force)
  uninstall   Remove installed skill and managed instruction blocks
  doctor      Show detected targets and installation status

Options:
  --agent codex|claude|both|auto      Target agent(s), default: auto
  --scope global|local                Install scope, default: global
  --project-root <path>               Project root for local scope, default: current dir
  --with-instructions                 Add/update managed instruction block (default)
  --without-instructions              Do not touch instruction files
  --keep-instructions                 For uninstall: keep managed blocks
  --force                             Overwrite destination if it exists
  --repo <owner/repo>                 GitHub repository for bootstrap mode, default: Xopoko/SignatureMap
  --ref <git-ref>                     Git ref for bootstrap mode, default: main
  --source local|github|auto          Package source mode, default: auto
  --codex-home <path>                 Override Codex home directory
  --claude-home <path>                Override Claude home directory
  --codex-layout auto|codex|agents    Local Codex folder layout for project scope, default: auto
  --dry-run                           Print planned actions only
  --verbose                           Verbose logs
  --version                           Print installer version
  -h, --help                          Show help

Examples:
  ./install.sh
  ./install.sh install --agent both --scope local --project-root "$PWD"
  ./install.sh update --agent codex --scope global
  ./install.sh uninstall --agent claude --scope local --project-root "$PWD"
  ./install.sh doctor --agent auto --scope global

Remote one-line install:
  curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<ref>/install.sh | bash -s -- install --repo <owner/repo> --ref <ref>
USAGE
}

log() {
  local level="$1"
  shift
  case "${level}" in
    debug)
      if [[ "${VERBOSE}" == "1" ]]; then
        printf '[debug] %s\n' "$*" >&2
      fi
      ;;
    info)
      printf '[info] %s\n' "$*" >&2
      ;;
    warn)
      printf '[warn] %s\n' "$*" >&2
      ;;
    error)
      printf '[error] %s\n' "$*" >&2
      ;;
  esac
}

die_usage() {
  log error "$*"
  usage >&2
  exit "${EXIT_USAGE}"
}

die_runtime() {
  log error "$*"
  exit "${EXIT_RUNTIME}"
}

run_cmd() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

ensure_dir() {
  run_cmd mkdir -p "$1"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die_runtime "required command not found: $1"
}

normalize_abs() {
  local p="$1"
  if [[ -d "${p}" ]]; then
    (cd "${p}" && pwd)
  else
    local parent
    parent="$(cd "$(dirname "${p}")" && pwd)"
    printf '%s/%s\n' "${parent}" "$(basename "${p}")"
  fi
}

is_valid_source_root() {
  local root="$1"
  [[ -f "${root}/SKILL.md" ]] && [[ -x "${root}/scripts/sigmap" ]] && [[ -x "${root}/scripts/generate-signatures.sh" ]]
}

download_github_source() {
  local repo="$1"
  local ref="$2"
  local tmp
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t sigmap-install)"
  local archive_url="https://codeload.github.com/${repo}/tar.gz/${ref}"
  require_cmd curl
  require_cmd tar

  log info "downloading ${archive_url}"
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '%s\n' "${tmp}/source"
    return 0
  fi

  if ! curl -fsSL "${archive_url}" -o "${tmp}/source.tar.gz"; then
    log error "failed to download GitHub archive: ${archive_url}"
    return "${EXIT_RUNTIME}"
  fi
  if ! tar -xzf "${tmp}/source.tar.gz" -C "${tmp}"; then
    log error "failed to extract GitHub archive"
    return "${EXIT_RUNTIME}"
  fi

  local extracted
  extracted="$(find "${tmp}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "${extracted}" ]]; then
    log error "failed to resolve extracted source directory"
    return "${EXIT_RUNTIME}"
  fi
  if ! is_valid_source_root "${extracted}"; then
    log error "downloaded source does not contain required skill files"
    return "${EXIT_RUNTIME}"
  fi
  printf '%s\n' "${extracted}"
}

resolve_source_root() {
  local source_root=""
  local mode="${SOURCE_MODE}"

  if [[ "${mode}" == "local" || "${mode}" == "auto" ]]; then
    if is_valid_source_root "${SCRIPT_DIR}"; then
      source_root="${SCRIPT_DIR}"
      [[ "${mode}" == "local" ]] || {
        printf '%s\n' "${source_root}"
        return 0
      }
    elif [[ "${mode}" == "local" ]]; then
      die_runtime "--source local requested but current directory is not a valid skill package"
    fi
  fi

  if [[ "${mode}" == "github" || -z "${source_root}" ]]; then
    [[ -n "${REPO}" ]] || die_usage "--repo is required for GitHub bootstrap mode"
    if ! source_root="$(download_github_source "${REPO}" "${REF}")"; then
      die_runtime "failed to resolve source from GitHub (${REPO}@${REF})"
    fi
  fi

  printf '%s\n' "${source_root}"
}

resolve_codex_home() {
  if [[ -n "${CODEX_HOME_OVERRIDE}" ]]; then
    normalize_abs "${CODEX_HOME_OVERRIDE}"
    return 0
  fi
  if [[ -d "${HOME}/.codex" ]]; then
    printf '%s\n' "${HOME}/.codex"
    return 0
  fi
  if [[ -d "${HOME}/.agents" ]]; then
    printf '%s\n' "${HOME}/.agents"
    return 0
  fi
  printf '%s\n' "${HOME}/.codex"
}

resolve_local_codex_layout() {
  local project="$1"
  case "${CODEX_LAYOUT}" in
    codex)
      printf '.codex\n'
      return 0
      ;;
    agents)
      printf '.agents\n'
      return 0
      ;;
    auto)
      if [[ -d "${project}/.codex" ]]; then
        printf '.codex\n'
      elif [[ -d "${project}/.agents" ]]; then
        printf '.agents\n'
      else
        printf '.codex\n'
      fi
      return 0
      ;;
    *)
      die_usage "--codex-layout must be one of: auto, codex, agents"
      ;;
  esac
}

resolve_claude_home() {
  if [[ -n "${CLAUDE_HOME_OVERRIDE}" ]]; then
    normalize_abs "${CLAUDE_HOME_OVERRIDE}"
    return 0
  fi
  if [[ -n "${CLAUDE_HOME:-}" ]]; then
    normalize_abs "${CLAUDE_HOME}"
    return 0
  fi
  printf '%s\n' "${HOME}/.claude"
}

is_codex_detected() {
  local codex_home
  codex_home="$(resolve_codex_home)"
  [[ -d "${codex_home}" ]] || command -v codex >/dev/null 2>&1
}

is_claude_detected() {
  local claude_home
  claude_home="$(resolve_claude_home)"
  [[ -d "${claude_home}" ]] || command -v claude >/dev/null 2>&1
}

resolve_agents() {
  case "${AGENT}" in
    codex)
      printf 'codex\n'
      ;;
    claude)
      printf 'claude\n'
      ;;
    both)
      printf 'codex\nclaude\n'
      ;;
    auto)
      local any=0
      if is_codex_detected; then
        printf 'codex\n'
        any=1
      fi
      if is_claude_detected; then
        printf 'claude\n'
        any=1
      fi
      if [[ "${any}" == "0" ]]; then
        die_runtime "no supported agent environment detected (codex/claude)"
      fi
      ;;
    *)
      die_usage "--agent must be one of: codex, claude, both, auto"
      ;;
  esac
}

codex_cmd_for_scope() {
  local scope="$1"
  local codex_home="$2"
  local local_layout="${3:-.codex}"
  if [[ "${scope}" == "global" ]]; then
    if [[ "${codex_home}" == "${HOME}/.agents" ]]; then
      printf '%s\n' '${CODEX_HOME:-$HOME/.agents}/skills/signature-map/scripts/sigmap'
    else
      printf '%s\n' '${CODEX_HOME:-$HOME/.codex}/skills/signature-map/scripts/sigmap'
    fi
  else
    printf './%s/skills/signature-map/scripts/sigmap\n' "${local_layout}"
  fi
}

claude_cmd_for_scope() {
  local scope="$1"
  if [[ "${scope}" == "global" ]]; then
    printf '%s\n' '${CLAUDE_HOME:-$HOME/.claude}/skills/signature-map/scripts/sigmap'
  else
    printf '%s\n' './.claude/skills/signature-map/scripts/sigmap'
  fi
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/|&]/\\&/g'
}

render_template() {
  local template_path="$1"
  local sigmap_cmd="$2"
  local scope_label="$3"
  local target_kind="$4"
  local escaped_cmd
  local escaped_scope
  local escaped_target
  escaped_cmd="$(escape_sed_replacement "${sigmap_cmd}")"
  escaped_scope="$(escape_sed_replacement "${scope_label}")"
  escaped_target="$(escape_sed_replacement "${target_kind}")"
  sed \
    -e "s|{{SIGMAP_CMD}}|${escaped_cmd}|g" \
    -e "s|{{SCOPE_LABEL}}|${escaped_scope}|g" \
    -e "s|{{TARGET_KIND}}|${escaped_target}|g" \
    "${template_path}"
}

upsert_managed_block() {
  local target_file="$1"
  local block_content="$2"
  local tmp
  tmp="$(mktemp)"

  local block
  block="${BEGIN_TAG}
${block_content}
${END_TAG}"

  if [[ -f "${target_file}" ]] && grep -Fq "${BEGIN_TAG}" "${target_file}" && grep -Fq "${END_TAG}" "${target_file}"; then
    local start end
    start="$(grep -nF "${BEGIN_TAG}" "${target_file}" | head -n 1 | cut -d: -f1)"
    end="$(grep -nF "${END_TAG}" "${target_file}" | tail -n 1 | cut -d: -f1)"
    if [[ -n "${start}" && -n "${end}" ]] && (( start < end )); then
      {
        if (( start > 1 )); then
          head -n $((start - 1)) "${target_file}"
        fi
        printf '%s\n' "${BEGIN_TAG}"
        printf '%s\n' "${block_content}"
        printf '%s\n' "${END_TAG}"
        tail -n +$((end + 1)) "${target_file}" || true
      } >"${tmp}"
    else
      {
        cat "${target_file}"
        printf '\n%s\n' "${block}"
      } >"${tmp}"
    fi
  elif [[ -f "${target_file}" ]]; then
    {
      cat "${target_file}"
      printf '\n%s\n' "${block}"
    } >"${tmp}"
  else
    printf '%s\n' "${block}" >"${tmp}"
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[dry-run] update managed block in %s\n' "${target_file}"
    rm -f "${tmp}"
    return 0
  fi

  ensure_dir "$(dirname "${target_file}")"
  mv "${tmp}" "${target_file}"
}

remove_managed_block() {
  local target_file="$1"
  [[ -f "${target_file}" ]] || return 0
  grep -Fq "${BEGIN_TAG}" "${target_file}" || return 0
  grep -Fq "${END_TAG}" "${target_file}" || return 0

  local start end tmp
  start="$(grep -nF "${BEGIN_TAG}" "${target_file}" | head -n 1 | cut -d: -f1)"
  end="$(grep -nF "${END_TAG}" "${target_file}" | tail -n 1 | cut -d: -f1)"
  [[ -n "${start}" && -n "${end}" ]] || return 0
  (( start < end )) || return 0

  tmp="$(mktemp)"
  {
    if (( start > 1 )); then
      head -n $((start - 1)) "${target_file}"
    fi
    tail -n +$((end + 1)) "${target_file}" || true
  } >"${tmp}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[dry-run] remove managed block from %s\n' "${target_file}"
    rm -f "${tmp}"
    return 0
  fi

  mv "${tmp}" "${target_file}"
}

copy_skill_payload() {
  local provider="$1"
  local source_root="$2"
  local dest_dir="$3"

  if [[ -e "${dest_dir}" ]]; then
    if [[ "${FORCE}" == "1" ]]; then
      run_cmd rm -rf "${dest_dir}"
    else
      die_runtime "destination exists: ${dest_dir} (use --force)"
    fi
  fi

  ensure_dir "${dest_dir}"
  run_cmd cp "${source_root}/SKILL.md" "${dest_dir}/SKILL.md"
  run_cmd cp -R "${source_root}/scripts" "${dest_dir}/scripts"

  if [[ "${provider}" == "codex" ]] && [[ -f "${source_root}/agents/openai.yaml" ]]; then
    ensure_dir "${dest_dir}/agents"
    run_cmd cp "${source_root}/agents/openai.yaml" "${dest_dir}/agents/openai.yaml"
  fi

  run_cmd chmod +x "${dest_dir}/scripts/sigmap" "${dest_dir}/scripts/generate-signatures.sh"
  run_cmd rm -rf "${dest_dir}/scripts/.bin" "${dest_dir}/scripts/__pycache__"
}

install_for_provider() {
  local provider="$1"
  local source_root="$2"
  local status=0

  local skill_dir=""
  local instructions_file=""
  local sigmap_cmd=""
  local scope_label=""

  case "${provider}" in
    codex)
      local codex_home
      codex_home="$(resolve_codex_home)"
      if [[ "${SCOPE}" == "global" ]]; then
        skill_dir="${codex_home}/skills/${SKILL_NAME}"
        instructions_file="${codex_home}/AGENTS.md"
        sigmap_cmd="$(codex_cmd_for_scope global "${codex_home}")"
      else
        local root local_layout
        root="${PROJECT_ROOT}"
        local_layout="$(resolve_local_codex_layout "${root}")"
        skill_dir="${root}/${local_layout}/skills/${SKILL_NAME}"
        instructions_file="${root}/AGENTS.md"
        sigmap_cmd="$(codex_cmd_for_scope local "${codex_home}" "${local_layout}")"
      fi
      scope_label="${SCOPE} codex"
      ;;
    claude)
      local claude_home
      claude_home="$(resolve_claude_home)"
      if [[ "${SCOPE}" == "global" ]]; then
        skill_dir="${claude_home}/skills/${SKILL_NAME}"
        instructions_file="${claude_home}/CLAUDE.md"
        sigmap_cmd="$(claude_cmd_for_scope global)"
      else
        skill_dir="${PROJECT_ROOT}/.claude/skills/${SKILL_NAME}"
        instructions_file="${PROJECT_ROOT}/CLAUDE.md"
        sigmap_cmd="$(claude_cmd_for_scope local)"
      fi
      scope_label="${SCOPE} claude"
      ;;
    *)
      die_runtime "unknown provider: ${provider}"
      ;;
  esac

  log info "installing ${SKILL_NAME} for ${provider}: ${skill_dir}"
  copy_skill_payload "${provider}" "${source_root}" "${skill_dir}"

  if [[ "${WITH_INSTRUCTIONS}" == "1" ]]; then
    local template_path rendered
    template_path="${source_root}/templates/managed.md"
    [[ -f "${template_path}" ]] || die_runtime "missing template: ${template_path}"
    rendered="$(render_template "${template_path}" "${sigmap_cmd}" "${scope_label}" "${provider}")"
    upsert_managed_block "${instructions_file}" "${rendered}"
  fi

  printf 'installed provider=%s scope=%s skill_dir=%s\n' "${provider}" "${SCOPE}" "${skill_dir}"
  return "${status}"
}

uninstall_for_provider() {
  local provider="$1"
  local skill_dir=""
  local instructions_file=""

  case "${provider}" in
    codex)
      local codex_home
      codex_home="$(resolve_codex_home)"
      if [[ "${SCOPE}" == "global" ]]; then
        skill_dir="${codex_home}/skills/${SKILL_NAME}"
        instructions_file="${codex_home}/AGENTS.md"
      else
        local local_layout
        local_layout="$(resolve_local_codex_layout "${PROJECT_ROOT}")"
        skill_dir="${PROJECT_ROOT}/${local_layout}/skills/${SKILL_NAME}"
        instructions_file="${PROJECT_ROOT}/AGENTS.md"
      fi
      ;;
    claude)
      local claude_home
      claude_home="$(resolve_claude_home)"
      if [[ "${SCOPE}" == "global" ]]; then
        skill_dir="${claude_home}/skills/${SKILL_NAME}"
        instructions_file="${claude_home}/CLAUDE.md"
      else
        skill_dir="${PROJECT_ROOT}/.claude/skills/${SKILL_NAME}"
        instructions_file="${PROJECT_ROOT}/CLAUDE.md"
      fi
      ;;
    *)
      die_runtime "unknown provider: ${provider}"
      ;;
  esac

  if [[ -e "${skill_dir}" ]]; then
    log info "removing ${skill_dir}"
    run_cmd rm -rf "${skill_dir}"
  else
    log warn "skill directory not found for ${provider}: ${skill_dir}"
  fi

  if [[ "${KEEP_INSTRUCTIONS}" == "0" ]]; then
    remove_managed_block "${instructions_file}"
  fi

  printf 'uninstalled provider=%s scope=%s skill_dir=%s\n' "${provider}" "${SCOPE}" "${skill_dir}"
}

doctor_for_provider() {
  local provider="$1"
  local skill_dir=""
  local instructions_file=""

  case "${provider}" in
    codex)
      local codex_home
      codex_home="$(resolve_codex_home)"
      if [[ "${SCOPE}" == "global" ]]; then
        skill_dir="${codex_home}/skills/${SKILL_NAME}"
        instructions_file="${codex_home}/AGENTS.md"
      else
        local local_layout
        local_layout="$(resolve_local_codex_layout "${PROJECT_ROOT}")"
        skill_dir="${PROJECT_ROOT}/${local_layout}/skills/${SKILL_NAME}"
        instructions_file="${PROJECT_ROOT}/AGENTS.md"
      fi
      ;;
    claude)
      local claude_home
      claude_home="$(resolve_claude_home)"
      if [[ "${SCOPE}" == "global" ]]; then
        skill_dir="${claude_home}/skills/${SKILL_NAME}"
        instructions_file="${claude_home}/CLAUDE.md"
      else
        skill_dir="${PROJECT_ROOT}/.claude/skills/${SKILL_NAME}"
        instructions_file="${PROJECT_ROOT}/CLAUDE.md"
      fi
      ;;
  esac

  local status="ok"
  [[ -f "${skill_dir}/SKILL.md" ]] || status="missing_skill"

  local block_status="absent"
  if [[ -f "${instructions_file}" ]] && grep -Fq "${BEGIN_TAG}" "${instructions_file}" && grep -Fq "${END_TAG}" "${instructions_file}"; then
    block_status="present"
  fi

  printf 'provider=%s scope=%s status=%s skill_dir=%s instructions=%s managed_block=%s\n' \
    "${provider}" "${SCOPE}" "${status}" "${skill_dir}" "${instructions_file}" "${block_status}"

  [[ "${status}" == "ok" ]]
}

parse_args() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      install|update|uninstall|doctor)
        SUBCOMMAND="$1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --version)
        printf '%s\n' "${VERSION}"
        exit 0
        ;;
    esac
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)
        [[ $# -lt 2 ]] && die_usage "--agent requires a value"
        AGENT="$2"
        shift 2
        ;;
      --scope)
        [[ $# -lt 2 ]] && die_usage "--scope requires a value"
        SCOPE="$2"
        shift 2
        ;;
      --project-root)
        [[ $# -lt 2 ]] && die_usage "--project-root requires a value"
        PROJECT_ROOT="$2"
        shift 2
        ;;
      --with-instructions)
        WITH_INSTRUCTIONS=1
        shift
        ;;
      --without-instructions)
        WITH_INSTRUCTIONS=0
        shift
        ;;
      --keep-instructions)
        KEEP_INSTRUCTIONS=1
        shift
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --repo)
        [[ $# -lt 2 ]] && die_usage "--repo requires a value"
        REPO="$2"
        shift 2
        ;;
      --ref)
        [[ $# -lt 2 ]] && die_usage "--ref requires a value"
        REF="$2"
        shift 2
        ;;
      --source)
        [[ $# -lt 2 ]] && die_usage "--source requires a value"
        SOURCE_MODE="$2"
        shift 2
        ;;
      --codex-home)
        [[ $# -lt 2 ]] && die_usage "--codex-home requires a value"
        CODEX_HOME_OVERRIDE="$2"
        shift 2
        ;;
      --claude-home)
        [[ $# -lt 2 ]] && die_usage "--claude-home requires a value"
        CLAUDE_HOME_OVERRIDE="$2"
        shift 2
        ;;
      --codex-layout)
        [[ $# -lt 2 ]] && die_usage "--codex-layout requires a value"
        CODEX_LAYOUT="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --verbose)
        VERBOSE=1
        shift
        ;;
      --version)
        printf '%s\n' "${VERSION}"
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die_usage "unknown argument: $1"
        ;;
    esac
  done

  case "${SCOPE}" in
    global|local) ;;
    *) die_usage "--scope must be one of: global, local" ;;
  esac

  case "${SOURCE_MODE}" in
    auto|local|github) ;;
    *) die_usage "--source must be one of: auto, local, github" ;;
  esac

  case "${CODEX_LAYOUT}" in
    auto|codex|agents) ;;
    *) die_usage "--codex-layout must be one of: auto, codex, agents" ;;
  esac

  if [[ "${SCOPE}" == "local" ]]; then
    if [[ -z "${PROJECT_ROOT}" ]]; then
      PROJECT_ROOT="$(pwd)"
    fi
    PROJECT_ROOT="$(normalize_abs "${PROJECT_ROOT}")"
    [[ -d "${PROJECT_ROOT}" ]] || die_runtime "project root does not exist: ${PROJECT_ROOT}"
  fi

  if [[ "${SUBCOMMAND}" == "update" ]]; then
    FORCE=1
  fi
}

main() {
  parse_args "$@"

  local providers
  providers="$(resolve_agents)"

  local source_root=""
  if [[ "${SUBCOMMAND}" == "install" || "${SUBCOMMAND}" == "update" ]]; then
    source_root="$(resolve_source_root)"
    log debug "source root: ${source_root}"
  fi

  local success=0
  local failed=0
  local provider
  while IFS= read -r provider; do
    [[ -n "${provider}" ]] || continue
    if case "${SUBCOMMAND}" in
      install|update)
        install_for_provider "${provider}" "${source_root}"
        ;;
      uninstall)
        uninstall_for_provider "${provider}"
        ;;
      doctor)
        doctor_for_provider "${provider}"
        ;;
      *)
        die_usage "unknown subcommand: ${SUBCOMMAND}"
        ;;
    esac; then
      success=$((success + 1))
    else
      failed=$((failed + 1))
      log warn "provider ${provider} failed"
    fi
  done <<<"${providers}"

  if [[ "${failed}" -gt 0 && "${success}" -gt 0 ]]; then
    exit "${EXIT_PARTIAL}"
  fi
  if [[ "${failed}" -gt 0 ]]; then
    exit "${EXIT_RUNTIME}"
  fi

  exit 0
}

main "$@"
