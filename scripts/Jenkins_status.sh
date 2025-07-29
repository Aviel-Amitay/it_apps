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