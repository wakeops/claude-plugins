#!/usr/bin/env bash
# Adds an EF Core migration for one DbContext, run from the project that holds the context.
#
#   add-migration.sh --project <dir> --context <full type name> [options] [migration-name]
#
#   --project <dir>      project directory containing the DbContext and its Migrations folder (required)
#   --context <type>     fully qualified DbContext type, e.g. MyApp.Data.AppDbContext (required)
#   --startup <dir>      startup project, only if the context has no IDesignTimeDbContextFactory
#   --output <dir>       migrations folder, relative to --project (default: Migrations)
#   --env <name>         ASPNETCORE_ENVIRONMENT / DOTNET_ENVIRONMENT for design time (default: Development)
#   --verbose            pass -v to dotnet ef
#
# Without a name, the migration is named <context>.<yyyy_MM_dd_HH_mm_ss> (context lowercased, without namespace), so
# names never collide between branches and sort in creation order.
set -euo pipefail

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }

project="" context="" startup="" output="Migrations" env_name="Development" verbose="" name=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project) project="${2:?--project needs a value}"; shift 2 ;;
        --context) context="${2:?--context needs a value}"; shift 2 ;;
        --startup) startup="${2:?--startup needs a value}"; shift 2 ;;
        --output)  output="${2:?--output needs a value}"; shift 2 ;;
        --env)     env_name="${2:?--env needs a value}"; shift 2 ;;
        --verbose) verbose="-v"; shift ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *) name="$1"; shift ;;
    esac
done
[[ -n "$project" && -n "$context" ]] || usage

command -v dotnet >/dev/null || { echo "dotnet is not on PATH." >&2; exit 1; }
dotnet ef --version >/dev/null 2>&1 || {
    echo "dotnet-ef is not installed. Install it: dotnet tool install --global dotnet-ef" >&2
    exit 1
}

[[ -d "$project" ]] || { echo "Project directory not found: $project" >&2; exit 1; }
[[ -n "$startup" ]] && startup="$(cd "$startup" && pwd)"
cd "$project"   # the design-time factory and appsettings lookups are relative to this directory

export ASPNETCORE_ENVIRONMENT="$env_name" DOTNET_ENVIRONMENT="$env_name"

short="${context##*.}"
name="${name:-$(tr '[:upper:]' '[:lower:]' <<<"$short").$(date +%Y_%m_%d_%H_%M_%S)}"

args=(migrations add "$name" -c "$context" -o "$output")
[[ -n "$startup" ]] && args+=(-s "$startup")
[[ -n "$verbose" ]] && args+=("$verbose")

dotnet ef "${args[@]}"

echo
echo "Created migration '$name'. Review it before committing:"
git status --short -- "$output" 2>/dev/null || true
