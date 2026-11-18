/// Loads pages in a real browser, for sites that ask every visitor to pass a
/// human check (such as Cloudflare). The in-app browser implements this and
/// shows the check to the person when it can't pass on its own.
abstract class PageLoader {
  Future<String> load(Uri url);
}
