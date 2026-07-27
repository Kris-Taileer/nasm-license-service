default rel

section .data
    secret_key: db 0x4B, 0x9F, 0x1A, 0xC3, 0x77, 0xE2, 0x05, 0x88
    secret_key_len: equ $ - secret_key

section .text
    global license_generate

; license[i] = name[i] XOR secret_key[i mod 8]
license_generate:
    xor rcx, rcx
.loop:
    cmp rcx, 32
    jge .done
    mov r8, rcx
    and r8, secret_key_len - 1   ; i mod 8, key len is a power of two
    mov al, [rdi + rcx]
    xor al, [secret_key + r8]
    mov [rsi + rcx], al
    inc rcx
    jmp .loop
.done:
    ret
