# Third-Party Notices

Omnie Agent bundles the following third-party assets. No other third-party
code or assets are bundled — everything else is Apple system frameworks.

## Unbounded (font)

- **Files:** `OmnieAgent/Resources/Fonts/Unbounded-Bold.ttf`,
  `OmnieAgent/Resources/Fonts/Unbounded-Black.ttf`
- **License:** SIL Open Font License 1.1 — full text in
  `OmnieAgent/Resources/Fonts/Unbounded-OFL.txt`
- **Source:** [Google Fonts / google/fonts](https://github.com/google/fonts/tree/main/ofl/unbounded)
- **Modification:** the two weights shipped here (Bold/700, Black/900) were
  instanced from Google's variable font release using `fonttools`, rather
  than bundling the full variable font — this app only uses the display
  font at 600–900 weight per `BRANDING.md`.
