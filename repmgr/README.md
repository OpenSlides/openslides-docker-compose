# Configuration of Primary and Standby Clusters

Upon starting, OpenSlides repmgr containers will always try to contact the
PgBouncer service to check whether a primary database cluster already exists.
If it does not, they will configure themselves according to the
`REPMGR_PRIMARY` environment variable if they are new clusters or simply
continue to start up according their existing configurations.

If, according to PgBouncer, a primary exists, the starting containers will
attempt to configure themselves to become hot standby clusters, following this
primary.  This is true even for clusters that are, up to that point, configured
as primaries themselves.  Ideally, failed primaries can automatically
reintegrate into their replication clusters this way.

Various factors can make automatic reintegration impossible, e.g., the specific
kind of failure that the primary has suffered or the amount of time for which
it was offline.  In such cases, user interaction is required to repair failed
nodes; however, additional self-healing measures could be added to the start-up
logic as needed.

# Security Considerations

## Postgres Permissions & Trusted Subnet

The database cluster nodes are designed to be used on their own subnet, e.g.,
within in a Docker Swarm.

A central database proxy service, such as PgBouncer, is supposed to act as
a bridge between the database subnet and application services.

Postgres restricts access to the various databases but all rules are based on
the assumption of a trusted subnet!

## SSH Access

Besides database connections, repmgr nodes can also connect to each other
through SSH (as user `postgres`).

The initial primary node generates SSH keys on first startup.  All keys, along
with pre-configured `known_hosts` and `authorized_keys` files, get stored in
a database in the cluster.

Secondary repmgr nodes can access the database after having cloned the database
cluster and install the SSH configuration locally.  This way, all repmgr nodes
share and trust the same SSH keys to gain access to and permit access from the
other repmgr nodes.

The database proxy is a less trusted service compared to the main repmgr nodes;
therefore, a separate SSH key is generated for the service.  Database policies
ensure that the proxy server's database access is limited to this particular
key.  On repmgr nodes, `authorized_keys` is used to limit the proxy's SSH key's
permissions to a minimum.  Currently, only the read-only command
`current-primary` is permitted.

## Known Issues

The trusted subnet setup is problematic because it requires and, worse, assumes
security to be provided on a lower level which the service itself cannot
verify.  A more explicit authentication system would be a great improvement
here.

Regarding the SSH key exchange, it would be a clear benefit to avoid storing
private keys in the database.  To improve upon the current method, repmgr nodes
could generate their own keys upon startup and store only their public keys in
the database.  The other repmgr nodes could be notified of new keys and add
them to their SSH configurations.  For this method to provide a real security
benefit, however, a solution for the aforementioned trusted subnet issue is
required first.
