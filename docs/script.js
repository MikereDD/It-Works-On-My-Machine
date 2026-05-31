// It-Works-On-My-Machine
// Tiny effects only. No framework nonsense.

document.addEventListener("DOMContentLoaded", () => {
  const target = document.querySelector(".cursor-target");

  if (target) {
    const cursor = document.createElement("span");
    cursor.className = "blink";
    cursor.textContent = "█";
    target.after(cursor);
  }

  const updated = document.getElementById("last-updated");
  if (updated) {
    const now = new Date();
    updated.textContent = now.toISOString().slice(0, 10);
  }

  console.log("It works on my machine.");
});