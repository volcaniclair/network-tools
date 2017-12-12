# network-tools

Tools for manipulating and querying network related configuration.

### Check network interface offload settings
```
$ ./offload.sh -h myhost -u myuser
```

This will iterate over the interfaces on the target host and produce a table containing the user editable settings.

Required Commands:
- ip
- ethtool

Yum based OS:
```
yum install iproute ethtool
```
