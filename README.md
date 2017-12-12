# network-tools

Tools for manipulating and querying network related configuration.

### Check network interface offload settings
```
$ ./offload.sh -h myhost -u myuser
```

This will iterate over a list of interfaces provided by a call to the 'ip addr' command and use ethtool to extract settings
