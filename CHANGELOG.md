# Changelog

Release notes for Shotkeeper, newest first. Every release needs a `## <version> (<date>)` section here: the release
workflow fails without one (`shotkeeper-cli release-plan`). The section becomes the GitHub Release text and the notes
in the app's update window. Write paragraphs and `- ` bullets; inline `code` works, other Markdown shows as plain text.

## 0.2.0 (2026-11-28)

The first release on GitHub Releases, signed with Shotkeeper's own certificate.

- Check for Updates… in the menu bar menu. Shotkeeper looks for a new version only when you choose it, and shows the
  release notes before anything is installed.
- Updates are downloaded from this repository's GitHub Releases and verified with Sparkle's signature before they are
  installed.
