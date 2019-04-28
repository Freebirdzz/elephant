;---------------------------------------------- loader 和 kernel 宏定义 --------------------------------------
LOADER_BASE_ADDR equ 0x900      ;载入内存中的位置
LOADER_START_SECTOR equ 0x2     ;存放在硬盘的第二扇区

;---------------------------------- gdt描述符属性 ------------------------------------------------------------
DESC_G_4K   equ    1_00000000000000000000000b         ;在段描述符中，G这个标志位，在高32位中的第23位，也就是它的右边有0-22，一共23个零。
DESC_D_32   equ    1_0000000000000000000000b          ;D为在高32位中的第22位，也就是它的右边有0-21，一共22个零
DESC_L      equ    0_000000000000000000000b           ;L为，右边一共21个零
DESC_AVL    equ    0_00000000000000000000b            ;64位代码标记，AVL位，右边20个零。此处标记为0便可
DESC_LIMIT_CODE2    equ    1111_0000000000000000b     ;段界限的第二部分（4位）。第一部分在低4字节中（16位）。一共有20位。右边16个零
DESC_LIMIT_DATA2    equ    DESC_LIMIT_CODE2
DESC_LIMIT_VIDEO2   equ    0000_0000000000000000b
DESC_P      equ    1_000000000000000b                 ;P位，表示段存在。右边15个零
DESC_DPL_0  equ    00_0000000000000b                  ;一共占用两位。表示的值从0-3，对应DPL，表示特权级。0是最高的。右边13个零。
DESC_DPL_1  equ    01_0000000000000b
DESC_DPL_2  equ    10_0000000000000b
DESC_DPL_3  equ    11_0000000000000b
DESC_S_CODE equ    1_000000000000b                    ;代码段S为。占用一位,值为1表示普通内存段，不是系统段。右边12个零
DESC_S_DATA equ    DESC_S_CODE
DESC_S_sys  equ    0_000000000000b
DESC_TYPE_CODE      equ    1000_00000000b             ;Type类型。参考书153页表格。右边8个零。代码段是可执行，非一致性，不可读，已访问为a清0
DESC_TYPE_DATA      equ    0010_00000000b             ;数据段；不可执行，向上扩展的，可写，已访问位a清0

;拼接出代码段高4字节内容
DESC_CODE_HIGH4     equ    (0x00 << 24) + DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + DESC_LIMIT_CODE2 + DESC_P + DESC_DPL_0 + DESC_S_CODE + DESC_TYPE_CODE + 0x00

;拼接数据段高4字节内容
DESC_DATA_HIGH4     equ    (0x00 << 24) +DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + DESC_LIMIT_DATA2 + DESC_P + DESC_DPL_0 + DESC_S_DATA + DESC_TYPE_DATA + 0x00

;拼接数据段高4字节内容。书上的内容最后的两个字节是0x00，但是对照163页对于显存放置位置的讲解，应该是0x0B才对,做了修改
DESC_VIDEO_HIGH4     equ    (0x00 << 24) +DESC_G_4K + DESC_D_32 + DESC_L + DESC_AVL + DESC_LIMIT_VIDEO2 + DESC_P + DESC_DPL_0 + DESC_S_DATA + DESC_TYPE_DATA + 0x0b


;---------------------------------- 选择子属性 ------------------------------------
RPL0    equ    00b
RPL1    equ    01b
RPL2    equ    10b
RPL3    equ    11b
TI_GDT  equ    000b
TI_LDT  equ    100b


PAGE_DIR_TABLE_POS  equ 0x100000
;---------------------------------- 页表相关属性 -------------------------------
PG_P    equ     1b
PG_W_R      equ 00b
PG_RW_W     equ 10b
PG_US_S     equ     000b
PG_US_U     equ     100b
