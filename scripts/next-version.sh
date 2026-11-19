#!/bin/bash
# Prints the next version from conventional commit messages read on stdin, or nothing when none warrants a release.
#   git log "v$last..HEAD" --no-merges --format=%B | bash scripts/next-version.sh "$last"
# BREAKING CHANGE or "type!:" -> major, "feat:" -> minor, "fix:" or "perf:" -> patch; docs, ci, chore, test... -> none.
IFS=. read -r major minor patch <<< "$1"
major_re='^[a-z]+(\([^)]*\))?!:'
feat_re='^feat(\([^)]*\))?:'
fix_re='^(fix|perf)(\([^)]*\))?:'
bump=""
while IFS= read -r line; do
    if [[ $line =~ $major_re || $line == "BREAKING CHANGE"* ]]; then bump=major; break
    elif [[ $line =~ $feat_re ]]; then bump=minor
    elif [[ $line =~ $fix_re && $bump != minor ]]; then bump=patch
    fi
done
case $bump in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
esac
