/*
 * kcompat.h: compatibilidad para compilar los drivers VirtIO de RHEL 5.3
 * (2.6.18-128.el5) contra el kernel de RHEL 5.1 (2.6.18-53.el5).
 * Se incluye antes de cada fuente con -include; las fuentes de Red Hat no
 * se modifican. Cada bloque indica qué falta en -53.
 */
#ifndef _KCOMPAT_VIRTIO_H
#define _KCOMPAT_VIRTIO_H

#include <linux/types.h>

/* bool/true/false: agregados a linux/types.h después de 2.6.18-53 */
#ifndef __KCOMPAT_BOOL
#define __KCOMPAT_BOOL
typedef _Bool bool;
#ifndef true
#define true 1
#endif
#ifndef false
#define false 0
#endif
#endif

/* uninitialized_var: agregado a linux/compiler.h después de 2.6.18-53 */
#ifndef uninitialized_var
#define uninitialized_var(x) x = x
#endif

#endif /* _KCOMPAT_VIRTIO_H */
