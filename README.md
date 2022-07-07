# build-raspi-system-image
Build script and other necessary resources for generating a customized
RPi system image for automation.

Clone this project into a folder and put other package folders outside
of this project folder to get image built out of source.

For config parameters please refer to RPi documentation:  
<https://www.raspberrypi.com/documentation/computers/linux_kernel.html>

GNU Mtools is needed to generate boot image.

raspi-kernel:  
Download from <https://github.com/raspberrypi/linux>

gcc-arm:  
Download from <https://developer.arm.com/Tools%20and%20Software/GNU%20Toolchain>

glibc:  
Download from <http://ftp.gnu.org/gnu/glibc>

busybox:  
Download from <https://www.busybox.net/downloads>

The system image will be generated in 'out' folder of this project.

Here is an example project folder structure:

```
/
├── build-raspi-system-image
│   └── busybox_config
│
├── raspi-kernel
│
├── gcc-arm
│
├── glibc
│
└── busybox
```

Before build the image, enter busybox folder to customize the features
needed by the image and copy generated '.config' to this project folder
and rename it 'busybox_config'.

Then step into this project folder and execute build.sh to generate a
customized RPi system image.
