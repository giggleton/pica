//! The NIF behind `Pica.Native`.
//!
//! Every function here must return an error term for bad font data rather than panic: Rustler turns
//! a panic into a raise, but a panic on font data is a bug.

/// The crate's own version, so a caller can see which build of the NIF is loaded.
#[rustler::nif]
fn crate_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

rustler::init!("Elixir.Pica.Native");
