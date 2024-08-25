* fold - fold line
*
* Itagaki Fumihiko 18-Apr-94  Create.
* 1.0
*
* Usage: fold [ -bnsBCZ ] [ -w width ] [ -width ] [ -- ] [ <ファイル> ] ...

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref isdigit
.xref issjis
.xref atou
.xref strlen
.xref strfor1
.xref memmovi
.xref strip_excessive_slashes
.xref divul

DEFAULT_WIDTH	equ	80

TABSTOP		equ	8

STACKSIZE	equ	2048

READ_MAX_TO_OUTPUT_TO_COOKED	equ	8192
INPBUFSIZE_MIN	equ	258
OUTBUF_SIZE	equ	8192

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_b		equ	0	*  -b
FLAG_n		equ	1	*  -n
FLAG_s		equ	2	*  -s
FLAG_B		equ	3	*  -B
FLAG_C		equ	4	*  -C
FLAG_Z		equ	5	*  -Z
FLAG_can_seek	equ	6
FLAG_eof	equ	7
FLAG_saving	equ	8
FLAG_seek	equ	9


.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	bss_top(pc),a6
		lea	stack_bottom(a6),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin(a6)
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		moveq	#0,d6				*  D6.W : エラー・コード
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d5				*  D5.L : フラグ
		move.l	#DEFAULT_WIDTH,width(a6)
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		tst.b	1(a0)
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0),d0
		bsr	isdigit
		beq	parse_width

		addq.l	#1,a0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		cmp.b	#'w',d0
		beq	parse_width

		moveq	#FLAG_b,d1
		cmp.b	#'b',d0
		beq	set_option

		moveq	#FLAG_n,d1
		cmp.b	#'n',d0
		beq	set_option

		moveq	#FLAG_s,d1
		cmp.b	#'s',d0
		beq	set_option

		cmp.b	#'B',d0
		beq	option_B_found

		cmp.b	#'C',d0
		beq	option_C_found

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
usage:
		lea	msg_usage(pc),a0
		bsr	werror
exit_1:
		moveq	#1,d6
		bra	exit_program

parse_width:
		tst.b	(a0)
		bne	parse_width_1

		subq.l	#1,d7
		bcs	too_few_args

		addq.l	#1,a0
parse_width_1:
		bsr	atou
		bne	bad_width

		tst.b	(a0)+
		bne	bad_width

		move.l	d1,width(a6)
		beq	bad_width
		bra	decode_opt_loop1

too_few_args:
		lea	msg_too_few_args(pc),a0
werror_usage:
		bsr	werror_myname_and_msg
		bra	usage

bad_width:
		lea	msg_bad_width(pc),a0
		bra	werror_usage

option_B_found:
		bclr	#FLAG_C,d5
		bset	#FLAG_B,d5
		bra	set_option_done

option_C_found:
		bclr	#FLAG_B,d5
		bset	#FLAG_C,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
		moveq	#1,d0				*  出力は
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering(a6)
		beq	input_max			*  -- block device

		*  character device
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	input_max

		*  cooked character device
		move.l	#READ_MAX_TO_OUTPUT_TO_COOKED,d0
		btst	#FLAG_B,d5
		bne	inpbufsize_ok

		bset	#FLAG_C,d5			*  改行を変換する
		bra	inpbufsize_ok

input_max:
		move.l	#$00ffffff,d0
inpbufsize_ok:
		move.l	d0,read_size(a6)
		*  出力バッファを確保する
		tst.b	do_buffering(a6)
		beq	outbuf_ok

		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free(a6)
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outbuf_top(a6)
		move.l	d0,outbuf_ptr(a6)
outbuf_ok:
		*  入力バッファを確保する
		move.l	#$00ffffff,d0
		bsr	malloc
		sub.l	#$81000000,d0
		cmp.l	#INPBUFSIZE_MIN,d0
		blo	insufficient_memory

		move.l	d0,inpbuf_size(a6)
		bsr	malloc
		bmi	insufficient_memory
inpbuf_ok:
		move.l	d0,inpbuf_top(a6)
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin(a6)
		bmi	start_do_files

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
start_do_files:
	*
	*  開始
	*
		tst.l	d7
		beq	do_stdin
for_file_loop:
		subq.l	#1,d7
		movea.l	a0,a1
		bsr	strfor1
		exg	a0,a1
		cmpi.b	#'-',(a0)
		bne	do_file

		tst.b	1(a0)
		bne	do_file
do_stdin:
		lea	msg_stdin(pc),a0
		move.l	stdin(a6),d0
		bmi	open_file_failure

		move.w	d0,handle(a6)
		bsr	fold_one
		bra	for_file_continue

do_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
		tst.l	d0
		bmi	open_file_failure

		move.w	d0,handle(a6)
		bsr	fold_one
		move.w	handle(a6),-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
for_file_continue:
		movea.l	a1,a0
		tst.l	d7
		bne	for_file_loop

		bsr	flush_outbuf
exit_program:
		move.l	stdin(a6),d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
exit_program_1:
		move.w	d6,-(a7)
		DOS	_EXIT2

open_file_failure:
		bsr	werror_myname_and_msg
		lea	msg_open_fail(pc),a0
		bsr	werror
		moveq	#2,d6
		bra	for_file_continue
****************************************************************
* fold_one
****************************************************************
fold_one:
		btst	#FLAG_Z,d5
		sne	terminate_by_ctrlz(a6)
		sf	terminate_by_ctrld(a6)
		move.w	handle(a6),d0
		bsr	is_chrdev
		beq	fold_one_1			*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	fold_one_1

		st	terminate_by_ctrlz(a6)
		st	terminate_by_ctrld(a6)
fold_one_1:
		bset	#FLAG_can_seek,d5
		moveq	#1,d0
		bsr	seek_absolute
		cmp.l	#1,d0
		beq	fold_one_2

		bclr	#FLAG_can_seek,d5
fold_one_2:
		moveq	#0,d0
		bsr	seek_absolute
		beq	fold_one_3

		bclr	#FLAG_can_seek,d5
fold_one_3:
		bclr	#FLAG_eof,d5
		bclr	#FLAG_saving,d5
		movea.l	inpbuf_top(a6),a3
		moveq	#0,d3
fold_one_loop1:
		moveq	#0,d4				*  D4.L : location counter
fold_one_loop2:
		bsr	getc
fold_one_loop3:
		bmi	fold_one_eof

		cmp.b	#LF,d0
		beq	fold_one_lf

		cmp.b	#CR,d0
		beq	fold_one_cr

		cmp.b	#HT,d0
		beq	fold_one_ht

		cmp.b	#' ',d0
		beq	fold_one_sp

		btst	#FLAG_n,d5
		bne	fold_one_check_sjis

		btst	#FLAG_b,d5
		bne	fold_one_ascii
fold_one_check_sjis:
		bsr	issjis
		beq	fold_one_sjis

		btst	#FLAG_b,d5
		bne	fold_one_ascii

		cmp.b	#BS,d0
		beq	fold_one_bs
fold_one_ascii:
		moveq	#1,d1
		bsr	test_fold
		bmi	fold_one_loop2
fold_one_forward:
		bsr	fold_one_putc
		add.l	d1,d4
		bra	fold_one_loop2

fold_one_sjis:
		moveq	#2,d1
		bsr	test_fold
		bmi	fold_one_loop2

		bsr	fold_one_putc
		bsr	getc
		bpl	fold_one_forward
fold_one_eof:
		moveq	#0,d0
flush_saved:
		btst	#FLAG_saving,d5
		beq	flush_saved_return

		movem.l	d1-d2,-(a7)
		move.l	d0,d2
		bsr	seek_back
		move.l	d0,d1
		sub.l	d2,d1
flush_saved_loop1:
		subq.l	#1,d1
		bcs	flush_saved_loop2

		bsr	getc
		bsr	putc
		bra	flush_saved_loop1

flush_saved_loop2:
		subq.l	#1,d2
		bcs	flush_saved_done

		bsr	getc
		bra	flush_saved_loop2

flush_saved_done:
		movem.l	(a7)+,d1-d2
flush_saved_return:
		rts

fold_one_bs:
		bsr	fold_one_putc
		tst.l	d4
		beq	fold_one_bs_1

		subq.l	#1,d4
fold_one_bs_1:
		bra	fold_one_loop2

fold_one_cr:
		bsr	getc
		cmp.l	#LF,d0
		beq	fold_one_crlf

		btst	#FLAG_b,d5
		beq	fold_one_cr_normal

		moveq	#1,d1
		bsr	test_fold
		bmi	fold_one_loop2

		add.l	d1,d4
		bra	fold_one_cr_forward

fold_one_cr_normal:
		moveq	#0,d4
fold_one_cr_forward:
		move.l	d0,-(a7)
		moveq	#CR,d0
		bsr	fold_one_putc
		move.l	(a7)+,d0
		bra	fold_one_loop3

fold_one_crlf:
		moveq	#2,d0
		bsr	flush_saved
		bra	fold_one_put_crlf

fold_one_lf:
		moveq	#1,d0
		bsr	flush_saved
		btst	#FLAG_C,d5
		beq	fold_one_put_lf
fold_one_put_crlf:
		moveq	#CR,d0
		bsr	putc
fold_one_put_lf:
		moveq	#LF,d0
		bsr	putc
		bra	fold_one_loop1

fold_one_sp:
		moveq	#1,d1
fold_one_sp_1:
		bsr	test_fold
		bmi	fold_one_loop2

		move.l	d0,-(a7)
		moveq	#1,d0
		bsr	flush_saved
		move.l	(a7)+,d0
		bsr	putc
		add.l	d1,d4
		btst	#FLAG_s,d5
		beq	fold_one_loop2

		bset	#FLAG_saving,d5
		clr.l	saved_count(a6)
		bclr	#FLAG_seek,d5
		bra	fold_one_loop2

fold_one_ht:
		btst	#FLAG_b,d5
		bne	fold_one_sp

		move.l	d0,-(a7)
		moveq	#TABSTOP,d1
		move.l	d4,d0
		bsr	divul
		subq.l	#TABSTOP,d1
		neg.l	d1
		move.l	(a7)+,d0
		bra	fold_one_sp_1
*****************************************************************
test_fold:
		movem.l	d1,-(a7)
		add.l	d4,d1
		cmp.l	width(a6),d1
		movem.l	(a7)+,d1
		bls	test_fold_return

		move.l	d0,-(a7)
		moveq	#CR,d0
		bsr	putc
		moveq	#LF,d0
		bsr	putc
		moveq	#0,d4
		btst	#FLAG_saving,d5
		beq	do_fold_return

		bsr	seek_back
		move.l	(a7)+,d0
		moveq	#-1,d1
		rts

do_fold_return:
		move.l	(a7)+,d0
test_fold_return:
		cmp.w	d0,d0
		rts
*****************************************************************
seek_back:
		move.l	saved_count(a6),d0
		beq	seek_back_return

		btst	#FLAG_seek,d5
		beq	seek_back_1

		move.l	seek_count(a6),d0
		bsr	seek_relative
		bmi	read_fail

		movea.l	inpbuf_top(a6),a3
		moveq	#0,d3
		bclr	#FLAG_eof,d5
		move.l	saved_count(a6),d0
		bra	seek_back_return

seek_back_1:
		suba.l	d0,a3
		add.l	d0,d3
seek_back_return:
		bclr	#FLAG_saving,d5
		rts
*****************************************************************
getc:
		subq.l	#1,d3
		bcc	getc_get1

		btst	#FLAG_eof,d5
		bne	getc_eof

		move.l	inpbuf_top(a6),d0
		add.l	inpbuf_size(a6),d0
		sub.l	a3,d0
		bne	getc_read

		btst	#FLAG_saving,d5
		beq	getc_new

		btst	#FLAG_seek,d5
		bne	getc_new

		movem.l	a0-a1,-(a7)
		move.l	saved_count(a6),d0
		movea.l	a3,a1
		suba.l	d0,a1
		movea.l	inpbuf_top(a6),a0
		bsr	memmovi
		movea.l	a0,a3
		movem.l	(a7)+,a0-a1
		move.l	inpbuf_top(a6),d0
		add.l	inpbuf_size(a6),d0
		sub.l	a3,d0
		bne	getc_read

		btst	#FLAG_can_seek,d5
		beq	insufficient_memory

		bset	#FLAG_seek,d5
		move.l	saved_count(a6),d0
		neg.l	d0
		move.l	d0,seek_count(a6)
getc_new:
		movea.l	inpbuf_top(a6),a3
		move.l	inpbuf_size(a6),d0
getc_read:
		cmp.l	read_size(a6),d0
		bls	getc_read_1

		move.l	read_size(a6),d0
getc_read_1:
		move.l	d0,-(a7)
		move.l	a3,-(a7)
		move.w	handle(a6),-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,d3
		bmi	read_fail

		sub.l	d0,seek_count(a6)
		tst.b	terminate_by_ctrlz(a6)
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc
trunc_ctrlz_done:
		tst.b	terminate_by_ctrld(a6)
		beq	trunc_ctrld_done

		moveq	#CTRLD,d0
		bsr	trunc
trunc_ctrld_done:
		subq.l	#1,d3
		bcs	getc_eof
getc_get1:
		moveq	#0,d0
		move.b	(a3)+,d0
		addq.l	#1,saved_count(a6)
		tst.l	d0
		rts

getc_eof:
		bset	#FLAG_eof,d5
		moveq	#-1,d0
		rts
*****************************************************************
trunc:
		movem.l	d1/a0,-(a7)
		move.l	d3,d1
		beq	trunc_done

		movea.l	a3,a0
trunc_find_loop:
		cmp.b	(a0)+,d0
		beq	trunc_found

		subq.l	#1,d1
		bne	trunc_find_loop
		bra	trunc_done

trunc_found:
		subq.l	#1,a0
		move.l	a0,d3
		sub.l	a3,d3
		bset	#FLAG_eof,d5
trunc_done:
		movem.l	(a7)+,d1/a0
fold_one_putc_return:
		rts
*****************************************************************
fold_one_putc:
		btst	#FLAG_saving,d5
		bne	fold_one_putc_return
putc:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering(a6)
		bne	putc_buffering

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail
		bra	putc_done

putc_buffering:
		tst.l	outbuf_free(a6)
		bne	putc_buffering_1

		bsr	flush_outbuf
putc_buffering_1:
		movea.l	outbuf_ptr(a6),a0
		move.b	d0,(a0)+
		move.l	a0,outbuf_ptr(a6)
		subq.l	#1,outbuf_free(a6)
putc_done:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
flush_outbuf:
		move.l	d0,-(a7)
		tst.b	do_buffering(a6)
		beq	flush_return

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free(a6),d0
		beq	flush_return

		move.l	d0,-(a7)
		move.l	outbuf_top(a6),-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		blo	write_fail

		move.l	outbuf_top(a6),d0
		move.l	d0,outbuf_ptr(a6)
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free(a6)
flush_return:
		move.l	(a7)+,d0
		rts
*****************************************************************
insufficient_memory:
		bsr	werror_myname
		lea	msg_no_memory(pc),a0
		bra	werror_exit_3
*****************************************************************
seek_absolute:
		clr.w	-(a7)
seeksub:
		move.l	d0,-(a7)
		move.w	handle(a6),-(a7)
		DOS	_SEEK
		addq.l	#8,a7
		tst.l	d0
		rts
*****************************************************************
seek_relative:
		move.w	#1,-(a7)
		bra	seeksub
*****************************************************************
read_fail:
		bsr	werror_myname_and_msg
		lea	msg_read_fail(pc),a0
		bra	werror_exit_3
*****************************************************************
write_fail:
		lea	msg_write_fail(pc),a0
werror_exit_3:
		bsr	werror
		moveq	#3,d6
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
is_chrdev:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## fold 1.0 ##  Copyright(C)1994 by Itagaki Fumihiko',0

msg_myname:		dc.b	'fold: ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_open_fail:		dc.b	': オープンできません',CR,LF,0
msg_read_fail:		dc.b	': 入力エラー',CR,LF,0
msg_write_fail:		dc.b	'fold: 出力エラー',CR,LF,0
msg_stdin:		dc.b	'- 標準入力 -',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_too_few_args:	dc.b	'引数が足りません',0
msg_bad_width:		dc.b	'幅の指定が正しくありません',0
msg_usage:		dc.b	CR,LF
	dc.b	'使用法:  fold [-bnsBCZ] [-w <幅>] [-<幅>] [--] [<ファイル>] ...',CR,LF,0
*****************************************************************
.bss
.even
bss_top:

.offset 0
stdin:			ds.l	1
inpbuf_top:		ds.l	1
inpbuf_size:		ds.l	1
outbuf_top:		ds.l	1
outbuf_ptr:		ds.l	1
outbuf_free:		ds.l	1
read_size:		ds.l	1
saved_count:		ds.l	1
seek_count:		ds.l	1
width:			ds.l	1
handle:			ds.w	1
do_buffering:		ds.b	1
terminate_by_ctrlz:	ds.b	1
terminate_by_ctrld:	ds.b	1
.even
			ds.b	STACKSIZE
.even
stack_bottom:

.bss
		ds.b 	stack_bottom
*****************************************************************

.end start
