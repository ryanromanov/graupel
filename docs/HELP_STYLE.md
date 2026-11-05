# Help style

How Graupel's Help is written. Follow it for every page, and check a page against it before committing.


## Pages

- One task or one topic per page. A task page is titled with a verb ("Complete words", "Change the font"); a
  topic page with a noun ("Language servers", "Line endings").
- Start with one or two sentences that say what the page is for. Then the steps, then anything else.
- Use numbered steps for anything done in order. One action per step. If a step has a result worth knowing,
  say it in the same step ("A list of suggestions appears.").
- End with "See also" links only when the linked page is a likely next step.
- Prefer one fuller page to several short ones. A page that only makes sense next to another becomes a section
  of it. When you merge a page, move its `<a name>` to the top of the new section, since the app's Help
  buttons find pages by anchor. `Scripts/checkHelp.py` checks this.
- English only for now.
- Screenshots only when words can't do the job, taken from the real app in light mode. They go stale with
  every interface change.


## Voice

- Write to the reader as "you". Present tense.
- Plain words and short sentences. If a sentence needs a second comma, it probably wants to be two sentences.
- Say what happens, not how good it is. Graupel does things; it isn't "powerful", "seamless", or "intuitive".
- When a behavior might surprise someone, give the reason in one sentence. Don't explain what's obvious.
- Be exact. "After three letters" is better than "after a few letters".
- Don't claim more than Graupel does. If it opens a PDF as raw text, say that, not that it "opens PDFs".
- Mention CotEditor only on the "About Graupel" page and in the release notes, to credit it.


## Not like an AI wrote it

These patterns make writing sound generated. Don't use them.

- Hype and filler words: *seamless, robust, powerful, effortless, intuitive, leverage, utilize, delve,
  streamline, elevate, enhance, empower, unlock, harness, crucial, vital, comprehensive.*
- Softeners that add nothing: *simply, just, easily, quickly, effortlessly, of course, note that, it's worth
  noting, keep in mind.*
- Openers and closers: "Whether you're…", "In this section…", "Let's…", "In summary…", a closing sentence
  that repeats the page.
- Sentence shapes: "not just X, but Y"; "X isn't Y — it's Z"; lists of three by habit; a question answered by
  the next sentence.
- Transitions that announce themselves: *Additionally, Moreover, Furthermore, That said.* Usually the
  sentence works without them.
- Em dashes as all-purpose glue. Use a period or a comma. At most one per page.
- Bold for emphasis. Bold is only for names on screen (menus, buttons, settings).
- Emoji, exclamation marks, and headings in Title Case With Every Word Capitalized.

If a sentence could appear unchanged in the help for any other app, it's probably filler. Cut it.


## Mechanics

- Menus: choose **File > Open**. Buttons and settings: click **Restart**, select **Suggest completions while
  typing**. Names on screen are bold and spelled exactly as shown.
- Keys: press Return, press Esc, press Command-S (spelled out, hyphenated, no symbols).
- Settings, never Preferences. Open them with **Graupel > Settings**, then click the pane, such as **Mode**.
- Headings in sentence case.
- Code, file names, and commands in code style: `boreas lsp`, `.bor`.


## Words

| Use | Not |
| --- | --- |
| language server | Language Server, LSP (except when explaining the term once) |
| Boreas | the Boreas language (once it's introduced) |
| suggestions, the suggestion list | completions, completion candidates, popup |
| problem, error | diagnostic, issue |
| choose (a menu item) | select, click on, go to |
| click (a button), select (a checkbox or item) | press (a button), tick, check |
| press (a key) | hit, type (for a single key) |
| Settings | Preferences |
| document, file | text file (unless the difference matters) |


## Example

> **Complete words**
>
> Graupel suggests words as you type. With a language server, such as the one for Boreas, the suggestions
> fit the place you're typing: names from your file, fields after a dot, built-in functions, and keywords.
>
> 1. Type the first letters of a word. After three letters, a list of suggestions appears.
> 2. Choose a word with the arrow keys and press Return, or keep typing to narrow the list.
>
> To show the list sooner, press Esc. To close it without choosing a word, press Esc again.
>
> Graupel shows suggestions as you type in code. To turn this off, choose **Graupel > Settings**, click
> **Mode**, and deselect **Suggest completions while typing**.
