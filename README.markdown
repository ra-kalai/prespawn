prespawn.lua
===================


About
-----
prespawn.lua is a command line program, who spawn, and respawn the same program.

spawned program file descriptor stdin / stdout / stderr are available through
HTTP and|or a tcp socket

Opts
-----

    usage: ./prespawn.lua [cmd to run]
    Available options are:
      -h help           Display this
      -t tcp-listen     tcp control port
      -w http-listen    http control port
      -m min-instance   min number of instance
      -k keep-around    keep around *n* read entry of stdout, stdin
      -r respawn-delay  set the minimum respawn delay in second
      -d debug          debug / verbose mode


License
-------
prespawn.lua is distributed under the terms
of the [GNU Lesser General Public License][lgpl].

[lgpl]: http://www.gnu.org/licenses/lgpl.html
