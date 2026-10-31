# Releasing Pica

A release goes in one order, and nothing but this file enforces it. Pica's users download a
prebuilt NIF from the GitHub release of their version, checked against the checksum file in the
Hex package, so the checksum file must be written from the published builds **before** the
package is published. Publishing first makes every user's download fail its check.

Publishing to Hex needs the maintainer's Hex keys; it is never done by an agent.

1. **Set the version.** In `mix.exs`, change `@version` from the `-dev` pre-release to the
   release, say `"0.1.0"`, and commit it. A `-dev` version always builds the NIF from source, so
   this is the commit the builds are made from.

2. **Tag and push.**

   ```bash
   git tag v0.1.0
   git push origin main v0.1.0
   ```

3. **Wait for the builds.** The `Release` workflow (`.github/workflows/release.yml`) builds the
   NIF for every target and attaches each build to the GitHub release named by the tag. Check that
   the release lists one archive per target before going on.

4. **Write the checksum file** from the published builds. `PICA_BUILD=1` builds the NIF locally
   while doing it, since the checksum file it writes does not exist yet:

   ```bash
   PICA_BUILD=1 mix rustler_precompiled.download Pica.Native --all --print
   ```

   It writes `checksum-Elixir.Pica.Native.exs`. Commit it and push.

5. **Check the package**, then publish it:

   ```bash
   mix hex.build --unpack
   mix hex.publish
   ```

   The unpacked package should hold `lib/`, the crate under `native/pica/` (so `PICA_BUILD=1`
   can build from Hex), the checksum file and the licence notices.

6. **Start the next version.** Set `@version` to the next `-dev` pre-release, such as
   `"0.1.1-dev"`, and commit it.
