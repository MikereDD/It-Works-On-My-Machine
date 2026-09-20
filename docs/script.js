(() => {
  const updated = document.getElementById("last-updated");

  if (updated) {
    fetch("https://api.github.com/repos/MikereDD/It-Works-On-My-Machine/commits/main", {
      headers: {
        Accept: "application/vnd.github+json"
      }
    })
      .then((response) => {
        if (!response.ok) throw new Error(`GitHub API returned ${response.status}`);
        return response.json();
      })
      .then((commit) => {
        const iso = commit?.commit?.committer?.date;
        if (!iso) throw new Error("Commit date was not present in the GitHub response");

        const date = iso.slice(0, 10);
        updated.dateTime = iso;
        updated.textContent = date;
      })
      .catch(() => {
        updated.textContent = "unavailable";
      });
  }

  console.log("It works on my machine.");
})();
