/*
Help Script for Table of Contents

 CotEditor
 https://coteditor.com

 © 2023-2025 1024jp
*/

// Graupel: follow the page's own Table of Contents link from the toolbar button, instead of building
//   the address from the page's location, which doesn't work on the book's start page in Help Viewer
const isTOC = window.location.pathname.endsWith("/toc.html")
const isPage = window.location.pathname.includes("/pgs/")

function tocLink() {
    return document.querySelector("a.toc");
}

// enable toc button in the viewer's toolbar
document.addEventListener("DOMContentLoaded", () => {
    function toggleTOC() {
        if (isTOC) {
            window.history.back();
            return;
        }
        const link = tocLink();
        if (link) {
            link.click();
        } else {
            window.location.href = isPage ? "../toc.html" : "toc.html";
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
            tocButton.href = "../toc.html";
            tocButton.textContent = "Table of Contents";
            document.body.prepend(tocButton);
    });
}
