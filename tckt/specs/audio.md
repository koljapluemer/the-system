Add a new primary type (@docs/adding-a-primary-type.md) `audio`.
It should be for stuff like (downloaded) podcast episodes or audio books.

Similar to `art`, allow attaching one media file per note; although in this case we want a new parallel folder (so it's easy to see the files), and limit to mp3, m4a, and other reasonable audio formats.
We also want to have a `tags` prop: Represented in the JSON as an array, this show up in the edit view as a typical tag adding bar: plaintext input, but with a smart dropdown to autocomplete to other tags that we have in the db, and once the user clicks a suggestion or presses enter/space we add a little badge for the tag w/ an icon button to remove it again. Maybe there is a little library or flutter pattern for this?

Then, based on this, we want a new flow: "Listen"

It should load a random audio, embedding it in an audio player (there must be a component for this, right? Nothing fancy, just play/pause, and dragging on the playback timeline, that sort of stuff).

Below the player, we want a column of buttons:
- Next (loads new random audio and ensures the audio that was just played will not show up today unless everything else eligible was also already listened to today)
- Hide for 1 Week (similar, but w/ 1 week until it's eligible again, and this means under any circumstance, even if nothing eligible)
- Hide for 2 Months
- Hide for 1 Year
- Never Listen Again

Above the player component, we want a by-tag filter. First should be a dropdown with the options ("or", "and", and "not"), and then the same UI pattern described above.
Only this time, we're not adding tags, we're filtering what is allowed for the next random load.
- `or`: only audio notes that contain any of the tags
- `and`: only audio notes containing all of the tags
- `not`: any audio notes except those containing any of the tags