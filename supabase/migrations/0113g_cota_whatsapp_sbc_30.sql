-- 0113g — COTA DIÁRIA DE WHATSAPP DE SÃO BERNARDO: 20 → 30 (28/10)
--
-- O Emerson viu "20 de 20 mensagens hoje" na fila de SBC e pediu para subir.
-- Fica igual à de Santo André (30). O intervalo de 3 min entre envios não muda.
-- Só dado: vale na hora, sem deploy (a tela lê o banco a cada envio).

update public.unidades set limite_whatsapp_dia = 30
 where id = '265f0c74-123e-4886-9683-b70793c30b61' and limite_whatsapp_dia = 20;
