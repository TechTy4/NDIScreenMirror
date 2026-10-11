# Documentation

This is the documentation index for Sanctuary NDI. The current application release is [v1.3.0](https://github.com/TechTy4/NDIScreenMirror/releases/tag/v1.3.0). Documentation was reviewed against that version on October 11, 2026.

## For operators and installers

- [Main README](../README.md): overview, installation, everyday operation, and build commands.
- [Deployment guide](../DEPLOYMENT.md): installing and trusting the app, initial configuration, and updates.
- [Settings reference](SETTINGS.md): every setting, default, save behavior, and monitor role.
- [Troubleshooting](TROUBLESHOOTING.md): permissions, startup recovery, source discovery, and incorrect screen content.
- [On-site acceptance checklist](TESTING.md#on-site-acceptance-checklist): what still needs testing with the sanctuary displays, Magewell, and livestream computer.

## For maintainers

- [Architecture](ARCHITECTURE.md): capture/send pipeline, display matching, recovery, receiver API, and security boundaries.
- [Testing and release verification](TESTING.md): automated checks, manual checks, recorded evidence, and packaging.
- [Changelog](../CHANGELOG.md): shipped versions and links to releases.
- [Conversation and decision record](CONVERSATION.md): the user's requests, implementation outcomes, and changes to the original scope.
- [Original build brief](ORIGINAL_BRIEF.md): the attached initial specification, preserved as historical context.

## Reading the history correctly

The original brief asked for one feed and explicitly excluded Magewell control and onboarding. Later requests superseded those boundaries: there are now two continuously running screen feeds, a mandatory startup wizard, optional confidence mirroring, and Magewell routing. Use the settings and architecture references for current behavior; use the original brief and conversation record to understand why it changed.

A successful local build or video receive test is not proof that the sanctuary network, three-monitor layout, or physical projector has passed acceptance. Those remaining checks are listed explicitly in the testing guide.

## Keeping these docs current

When changing settings, recovery, routing, or capture behavior, update the corresponding reference and tests. Record shipped changes in the changelog and add significant user decisions to the conversation record, identifying quotations versus summaries. Keep passwords, actual receiver credentials, local environment files, signing-account details, and captured screen contents out of public documentation.
