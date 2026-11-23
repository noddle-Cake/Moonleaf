# Android update review — November 23, 2026

Reviewed the published build 52, Gradle signing configuration, release workflow,
certificate guard, Settings link, and the deployment/mirror scripts on 5820.

- **High: deployment could corrupt a concurrent APK download.** The mirror
  locked its executable, which the deployment replaced, while deployment also
  removed in-progress files. Deploy and mirror now share a stable lock outside
  the served tree. Static deployment never deletes APKs, partial downloads or
  verified metadata. APKs and metadata are published with atomic replacements.
- **Medium: App Updates was only a browser link.** It could not compare
  versions or report download failures. It now reads the installed native
  version and signing identity, compares verified release metadata, shows notes,
  and supports streamed downloads, cancellation, retries and Android's installer.
- **Medium: a stale release response could select an older build.** The mirror
  now preserves newer published metadata and refuses to replace a version with
  different bytes. The app never offers an equal or older version as an update.

The permanent signing key and package ID remain unchanged. PR builds receive
no release signing credentials. Publication checks still reject a wrong key,
changed package, wrong build number, debug APK or unrecognized signer output.
The mirror also runs these checks and needs only the public certificate pin.
Checksums are verified in the mirror and app; Android rechecks the archive's
package, version and certificate before its standard install prompt is opened.

Builds 48 and earlier retain their one-time migration requirement. The updater
never removes an installation or touches library storage. The site explains
that uninstalling an old debug build removes local progress and highlights.
