/*
Help Script for Table of Contents

 CotEditor
 https://coteditor.com

 © 2023-2025 1024jp
*/

// Graupel: find the table of contents from this script's location rather than the page's,
//   which isn't a file path for every page Help Viewer shows, such as the book's start page
const tocURL = new URL("../../en.lproj/toc.html", document.currentScript.src).href
const isTOC = window.location.pathname.endsWith("/toc.html")
const isPage = window.location.pathname.includes("/pgs/")

// enable toc button in the viewer's toolbar
document.addEventListener("DOMContentLoaded", () => {
    function toggleTOC() {
        if (isTOC) {
            window.history.back();
        } else {
            window.location = tocURL;
        }
    }

    if ('HelpViewer' in window) {
        window.HelpViewer.showTOCButton(true, toggleTOC, toggleTOC);
    }
});

// insert ToC button
if (isPage) {
    document.addEventListener("DOMContentLoaded", () => {
            const tocButton = document.createElement("a");
            tocButton.className = "toc";
            tocButton.href = tocURL;
            tocButton.textContent = "Table of Contents";
            document.body.prepend(tocButton);
    });
}
