<h1 align="center">
  <img src="./snapshots/logo.png" width="48" alt="SpringNote-Agenda logo">
  SpringNote-Agenda
</h1>

<p align="center"><a href="./README.md">English</a> · <a href="./README.zh-CN.md">简体中文</a></p>

A desktop notebook for daily records, work plans, and AI-assisted summaries. Notes are saved as local Markdown files, so you can read, edit, and back them up independently.

## Features

- **Quick capture**: Record text and images from the home page and organize them into daily notes.
- **Notebook**: Create daily, weekly, monthly, and biweekly reports. Edit Markdown, search notes, and save changes automatically.
- **Work plans**: Keep monthly summaries and next-month plans together, with a separate weekly planning board.
- **Project calendar**: Collect dated tasks from notes and plans, track deadlines, and mark tasks complete.
- **AI assistance**: Generate summaries and reports, and use Memories to find and discuss past records.
- **Desktop and data settings**: Choose a data directory, configure WebDAV sync, and customize the tray, shortcuts, themes, and fonts.

## Get started

1. Download the installer for your platform from [Releases](https://github.com/Adorable-Qin/SpringNote-Agenda/releases/latest).
2. Open **Settings** and confirm your data directory. Keep this directory when updating or reinstalling to retain your notes and configuration.
3. To use AI features, add a provider and model in Settings, then select the default models. Use the provider's current connection details and model IDs. AI configuration is optional for writing and editing ordinary notes.
4. Capture a record on **Home**, or open **Notebook** and choose **New** to create a report for a date or period.

## Notebook

Choose a report type, then select a note to edit. Changes save automatically. Search applies to the selected type and requires at least two characters. Right-click a note to delete it after confirmation.

Under **Settings → Preferences → Notebook editor**, choose live editing or classic mode. Classic mode includes editing, split view, and preview; AI completion requires a compatible completion model.

For biweekly reporting, select **Biweekly** under **Settings → Preferences → Work cycle**, then combine two weekly reports. The original reports remain available.

## Work plans and calendar

Open **Work plans** from the sidebar. Monthly cards contain a summary and a plan for the following month. The weekly board lets you select and edit a saved week. Both save automatically.

Add a date to a task to include it in **Project Calendar**:

```markdown
- [ ] 2026-11-06 Finish the proposal
- [ ] Prepare release notes — Due: 2026-11-09
```

Date changes and task completion are reflected in the calendar. Completed tasks no longer appear as pending reminders.

## Data and AI

Notes, images, and configuration live in the selected data directory. Back up the whole directory to retain related files. WebDAV sync is optional and can be configured in Settings.

AI features send the relevant prompts and note content to the provider you configure. Review that configuration before using AI with sensitive records.

## Development

The application uses Flutter and a Rust backend. See the [application README](./spring_note/README.md) for setup and bridge-generation instructions. Run these commands from `spring_note/`:

```sh
flutter pub get
flutter run -d windows
flutter analyze
flutter test
```

## Documentation and feedback

- [Documentation](./docs/en/index.md)
- [Changelog](./CHANGELOG.md)
- [Report an issue](https://github.com/Adorable-Qin/SpringNote-Agenda/issues)

Include the app version, reproduction steps, and relevant error messages when reporting a problem. Thanks to everyone who contributes fixes and feedback.

## License

The project's original code and modifications are licensed under **AGPL-3.0-only**; see [LICENSE](./LICENSE). Third-party components retain their own copyright and license terms.
