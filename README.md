# folio-local-run

This script allows you to run set of modules that are all build straight
from source. Useful if you are debugging and testing new functionality
and need to test integration with other modules.

This probably only works on Ubuntu/Debian and likes with Postgresql 11
available or later.

At this point, the testing is performed without the remote registry.
It's completely isolated test with everything from source.

## Preparations

### Postgesql

The postgresql-13 Debian package is known to work.
Prepare a database for Okapi and modules. Could be separate databases,
could be one.

### ElasticSearch

The Debian package from
[www.elastic.so](https://www.elastic.co/guide/en/elasticsearch/reference/current/deb.html) is known to work.

Install plugins before use. 

    usr/share/elasticsearch/bin/elasticsearch-plugin install --batch \
      analysis-icu \
      analysis-kuromoji \
      analysis-smartcn \
      analysis-nori \
      analysis-phonetic

Note that if the elasticsearch is upgraded, then the plugins may have to
be re-installed.

If you run ElasticSearch on port 9200, there's less configuration
changes to be made later.

### Kafka

No Debian package at this point AFAIK. You'll have to download yourself.

In order to install as a service, it's good practice to make a dedicated
user for that.

Example with kafka installed in `/home/kafka`, so that
`/home/kafka/bin/` has the binaries. Two services should be installed:
`zookeeper.service` and `kafka.service`.

```
$ cat /etc/systemd/system/zookeeper.service 
[Unit]
Requires=network.target remote-fs.target
After=network.target remote-fs.target

[Service]
Type=simple
User=kafka
ExecStart=/home/kafka/bin/zookeeper-server-start.sh /home/kafka/config/zookeeper.properties
ExecStop=/home/kafka/bin/zookeeper-server-stop.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
```

```
$ cat /etc/systemd/system/kafka.service 
[Unit]
Requires=zookeeper.service
After=zookeeper.service

[Service]
Type=simple
User=kafka
ExecStart=/bin/sh -c '/home/kafka/bin/kafka-server-start.sh /home/kafka/config/server.properties > /home/kafka/kafka.log 2>&1'
ExecStop=/home/kafka/bin/kafka-server-stop.sh
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
```

If you run Kafka on port 9092, there's less configuration
changes to be made later.

### run.sh configuration

Adjust `run.sh` with the system configuration for PostgresQL,
Kafka, ElasticSearch and the modules you wish to run.

There are two sets of modules that you specify in the script.

The first set, `CORE_MODULES`, are modules that are installed
without mod-authoken enabled.

The second set, `TEST_MODULES`, are modules that are installed
after mod-authtoken is enabled.

You probably should never remove the 4 core modules, but you could
add more modules (all!) to that list (make `TEST_MODULES` empty).

It is important that the modules listed are same order as install
(or simulate install) would have returned. Okapi will fail if
dependences are not met - as expected.

## Running

At this point, the scripts here do not start Okapi, you'll have do it
yourself.

It is important that Okapi has the correct path to modules. It is relying
on the DeploymentDescriptor.json in target of each module to be correctly
configured. In particular the path to the (fat) jar file must be correct.

Use a directory structure with a common parent directory (I use `folio`) with
Okapi and all relevant modules checked out as well as folio-local-run (this
project). If there are modules missing, the folio-local-run script will
clone it for you. That might be what you want. But most certianly not
in all cases, as you are probably going to have a local build somewhere.

Start Okapi with current working directy in `okapi` - the parent directory
of `okapi-core`. In this case Okapi listens on port 9130 and uses ports range 9131 - 9200 for deployments:

    cd okapi
    java -Dport_end=9200 -jar okapi-core/target/okapi-core-fat.jar

Leave Okapi running or put it in the background - or something, but you
probably want to keep the log as you get log material from all modules
(which is useful).

You are now ready to run `run.sh`. In many cases it takes less than a minute
to start if all modules are cloned and compiled already.

    folio-local-run/run.sh

Observe that we execute run.sh in `folio` or other parent directory
that has Okapi and all modules!

By default the `run.sh` will purge on init which makes it start from a
clean slate. If you think something is wrong, just stop run.sh and Okapi.
Okapi will terminate all instances that it has deployed. The database
content is there for you to inspect. It will be purged next time, the
modules are installed.

If you don't want to purge on next run.sh invocation, say because you want
to test an upgrade, you'll have to modify the run.sh script.

If the install succeds and run.sh stops you can poke with your system.
You could also extend the run.sh and test something in that script.

To stop the system, just terminate Okapi!

Run run.sh to play with another set of modules and or different source for
any of the modules involved. Remember that the fat jar must be updated for this
to take an effect, so do not forget to run `mvn -DskipTests verify` or
`mvn -DskipTests install` on the module where you changed something.


