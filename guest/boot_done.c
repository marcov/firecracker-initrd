#include <unistd.h>

#define MAGIC_VALUE_SIGNAL_GUEST_BOOT_COMPLETE 123

#if defined(__aarch64__)
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>

#define MAGIC_IOPORT_SIGNAL_GUEST_BOOT_COMPLETE 0x40000000

static __inline void boot_done(void)
{
    int fd = open("/dev/mem", O_RDWR);
    int size = getpagesize();

    void* mem = mmap(NULL,
        size,
        PROT_READ | PROT_WRITE,
        MAP_SHARED,
        fd,
        MAGIC_IOPORT_SIGNAL_GUEST_BOOT_COMPLETE);
    close(fd);

    if (mem == MAP_FAILED) {
        return;
    }

    *(volatile char *)(mem) = MAGIC_VALUE_SIGNAL_GUEST_BOOT_COMPLETE;

    munmap(mem, size);
}
#endif /* __aarch64__ */

#if defined(__x86_64__)
#include <sys/io.h>

#define MAGIC_IOPORT_SIGNAL_GUEST_BOOT_COMPLETE 0x03f0
static __inline void
outb_p(unsigned char __value, unsigned short int __port)
{
    __asm__ __volatile__("outb %b0,%w1\noutb %%al,$0x80"
                         :
                         : "a"(__value),
                         "Nd"(__port));
}

static __inline void boot_done(void)
{
    iopl(3);
    outb_p(MAGIC_VALUE_SIGNAL_GUEST_BOOT_COMPLETE, MAGIC_IOPORT_SIGNAL_GUEST_BOOT_COMPLETE);
}
#endif /* __x86_64__ */

int main(int argc, char* const argv[])
{
    boot_done();
    return execv(OPENRC_INIT, argv);
}
