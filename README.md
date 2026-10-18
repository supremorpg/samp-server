# AppSync RP — fonte Pawn

Base didática de gamemode Pawn para SA-MP, com comunicação de estado entre servidor e cliente.

## Escopo

Este repositório contém somente fontes Pawn auditadas e arquivos de texto necessários ao desenvolvimento:

- `gamemodes/appsync.pwn`
- `gamemodes/colscan_points.generated.inc`
- `server.cfg.example`

Não distribui executáveis do servidor, compiladores Pawno, DLLs/plugins, AMX compilados, arquivos de runtime, dados de jogadores, credenciais ou automações de terceiros.

## Pré-requisitos

Obtenha o servidor e o compilador Pawn por canais oficiais/autorizados e instale os includes necessários, incluindo `a_samp`, fora deste repositório. Copie `server.cfg.example` para `server.cfg` e defina uma senha RCON forte, exclusiva e privada.

## Compilação

Compile `gamemodes/appsync.pwn` com uma instalação autorizada do compilador Pawn e implante somente os arquivos gerados no seu runtime privado. Não faça commit de `.amx`, executáveis ou arquivos de configuração reais.
