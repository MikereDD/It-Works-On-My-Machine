(() => {
  const updated = document.getElementById("last-updated");
  if (updated) updated.textContent = new Date().toISOString().slice(0, 10);
  console.log("It works on my machine.");
})();
