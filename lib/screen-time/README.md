# Screen time daemon

The countdown, the lock, the earning, and the ledger of a child install's screen time (`sudo omarchy-parent time`). Vendored from Jankees van Woezik's [omarchy-screen-time](https://github.com/jankeesvw/omarchy-screen-time) (MIT, see LICENSE) and adapted for kids mode: it runs as root under `/etc/omarchy/parent` and `/var/lib/omarchy/parent`, the parent password stands in for the PIN, the questions are grades 1 to 6, a set is `questions` for `minutes`, school hours pause the countdown instead of locking, and every change writes the `status.json` the lock screen and Math time read. `bin/omarchy-parent-timed` is the daemon, `bin/omarchy-parent-time-client` the client, and `omarchy-parent time` the parent's command over it.

Run the tests with `python3 lib/screen-time/tests/test_core.py`.
