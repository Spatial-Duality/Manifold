## Summary

What changed and why?

## Verification

List the commands you ran. Do not leave this blank.

- [ ] `swift test`
- [ ] `xcodebuild -project Manifold.xcodeproj -scheme Manifold -configuration Debug -derivedDataPath /tmp/manifold-derived-data build CODE_SIGNING_ALLOWED=NO`
- [ ] Other:

## Risk

- [ ] Runtime/XPC boundary preserved
- [ ] Standing access and tracked work block behavior kept separate
- [ ] No secrets, credentials, private files, signing keys, or personal data committed
- [ ] No workflows, dependabot config, or CODEOWNERS added

## Notes

Anything reviewers should know?
