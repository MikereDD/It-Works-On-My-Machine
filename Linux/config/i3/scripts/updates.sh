if command -v checkupdates >/dev/null 2>&1; then
    count=$(checkupdates 2>/dev/null | wc -l)
else
    count=0
fi
echo "$count"
