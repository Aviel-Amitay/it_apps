#!/bin/bash

################################################################################
# Jenkins Status
# Description: Automation script for 'Jenkins_status.sh'
# Author : Aviel Amitay
# GitHub : https://github.com/Aviel-Amitay/it_apps
# Modified: Apr 06 2026
################################################################################



RESULT=$(curl -s -u <username>:<token> http://x-ci03:8080/job/Chef/job/TestChefCookbooks/lastBuild/api/json | jq '.result'| sed 's/"//g')

if [[ "$RESULT" == "SUCCESS" ]]; then
  echo "Build succeeded"
elif [[ "$RESULT" == "null" ]]; then
  echo "⏳ Build is still in progress"
  echo ""
  echo "Find the status here >"
  echo "http://x-ci03:8080/job/Chef/job/TestChefCookbooks/lastBuild"
else
  echo "❌ Build failed or unstable (result: $RESULT)"
  echo "Check out the failed reason >"
  echo "http://x-ci03:8080/job/Chef/job/TestChefCookbooks/lastBuild"
fi