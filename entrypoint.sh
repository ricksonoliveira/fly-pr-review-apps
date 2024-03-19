#!/usr/bin/env bash

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

# Check the flyctl version
flyctl version

REPO_NAME=$(jq -r .repository.name /github/workflow/event.json)
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to {repo_name}-pr-{pr_number}
app="${INPUT_NAME:-$REPO_NAME-pr-$PR_NUMBER}"
# # Default the Fly app name to {repo_name}-pr-{pr_number}-postgres
postgres_app="${INPUT_POSTGRES:-$REPO_NAME-pr-$PR_NUMBER-postgres}"
region="${INPUT_REGION:-${FLY_REGION:-ord}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
dockerfile="$INPUT_DOCKERFILE"

# only wait for the deploy to complete if the user has requested the wait option
# otherwise detach so the GitHub action doesn't run as long
if [ "$INPUT_WAIT" = "true" ]; then
  detach=""
else
  detach="--detach"
fi

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# If PR is closed or merged, the app will be deleted
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true

  message="Review app deleted."
  echo "message=$message" >> $GITHUB_OUTPUT
  exit 0
fi

# Deploy the Fly app, creating it first if needed.
if ! flyctl status --app "$app"; then
  flyctl apps create --name "$app" --org "$org" --region "$region"

  # Attach postgres cluster and set the DATABASE_URL
  flyctl postgres attach "$postgres_app" --app "$app"
  flyctl deploy $detach --app "$app" --region "$region" --strategy immediate --remote-only

  statusmessage="Review app created. It may take a few minutes for the app to deploy."
elif [ "$EVENT_TYPE" = "synchronize" ]; then
  flyctl deploy $detach --app "$app" --region "$region" --strategy immediate --remote-only
  statusmessage="Review app updated. It may take a few minutes for your changes to be deployed."
fi

# Make some info available to the GitHub workflow.
flyctl status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)

echo "hostname=$hostname" >> $GITHUB_OUTPUT
echo "url=https://$hostname" >> $GITHUB_OUTPUT
echo "id=$appid" >> $GITHUB_OUTPUT
echo "name=$app" >> $GITHUB_OUTPUT