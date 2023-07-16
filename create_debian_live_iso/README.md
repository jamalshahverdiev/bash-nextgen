# Prepare Devian Live CD

## To prepare Debian Live CD just execute `prepare_iso.sh` script as following. As output it will create `debian-live.iso` file in the `/opt/livecd/` folder where you executed script `prepare_iso.sh`

```bash
$ ./prepare_iso.sh
```

### Test tool

```bash
$ apt install xinit qemu-system
$ qemu-system-x86_64 -drive file=/opt/livecd/debian-live.iso,format=raw
```