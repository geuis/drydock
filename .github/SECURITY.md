# Security policy

## Supported versions

Only the latest release of Drydock gets security fixes. Drydock checks for
new versions when it starts, and the latest release is always on the
[Releases page](https://github.com/geuis/drydock/releases/latest).

## Reporting a problem

Please don't report security problems in a public issue. Instead, report them
privately using
[Report a vulnerability](https://github.com/geuis/drydock/security/advisories/new)
on the repository's Security tab. Only the maintainer can see the report, and
it can be discussed and fixed there before anything is made public.

Helpful things to include:

- What the problem is and what someone could do with it
- The Drydock and macOS versions you used
- Steps or a file that shows the problem. If it involves a pilot file or
  plug-in, attach it zipped.

## What counts

Drydock reads files that often come from other people: plug-ins downloaded
from fan sites and pilot files shared between players. Examples of problems
worth reporting privately:

- A pilot file or plug-in that makes Drydock crash, hang, or read or write
  outside the file it was given
- A way to make the update check open a page that isn't a Drydock release
- A release download that isn't signed by Drydock's Developer ID or isn't
  notarized by Apple

Ordinary bugs, including crashes that don't come from a specially made file,
can go in a normal [issue](https://github.com/geuis/drydock/issues/new/choose).

## What to expect

Drydock is maintained in spare time, so there's no guaranteed response time.
Reports are acknowledged as soon as possible, and confirmed problems are
fixed in a new release with a security advisory explaining what was affected.
