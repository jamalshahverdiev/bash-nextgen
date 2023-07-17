# Prepare Devian Live CD

## To prepare Debian Live CD just execute `prepare_iso.sh` script as following. As output it will create `debian-live.iso` file in the `/opt/livecd/` folder

```bash
$ ./prepare_iso.sh
```

`Note:` If you want to add more packages to inside of the Debian ISO then just append it to the `packages.conf` file

### Test tool

```bash
$ apt install xinit qemu-system
$ qemu-system-x86_64 -drive file=/opt/livecd/debian-live.iso,format=raw
```
