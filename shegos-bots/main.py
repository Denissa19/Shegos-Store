ild_process.execFileSync(command.shift(), command, {
      // Without this, this install script strangely crashes with the error
      // "EACCES: permission denied, write" but only on Ubuntu Linux when node is
      // installed from the Snap Store. This is not a problem when you download
      // the official version of node. The problem appears to be that stderr
      // (i.e. file descriptor 2) isn't writable?
      //
      // More info:
      // - https://snapcraft.io/ (what the Snap Store is)
      // - https://nodejs.org/dist/ (download the official version of node)
      // - https://github.com/evanw/esbuild/issues/1711#issuecomment-1027554035
      //
      stdio: "pipe"
    }).toString().trim();
  } catch (err) {
    if (os2.platform() === "darwin" && /_SecTrustEvaluateWithError/.test(err + "")) {
      let os3 = "this version of macOS";
      try {
        os3 = "macOS " + child_process.execFileSync("sw_vers", ["-productVersion"]).toString().trim();
      } catch {
      }
      throw new Error(`The "esbuild" package cannot be installed because ${os3} is too outdated.

The Go compiler (which esbuild relies on) no longer supports ${os3},
which means the "esbuild" binary executable can't be run. You can either:

  * Update your version of macOS to one that the Go compiler supports
  * Use the "esbuild-wasm" package instead of the "esbuild" package
  * Build esbuild yourself using an older version of the Go compiler
`);
    }
    throw err;
  }
  if (stdout !== packageJSON.version) {
    throw new Error(`Exp