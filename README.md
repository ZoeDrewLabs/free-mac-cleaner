<p align="center">
  <img src="Resources/logo.webp" width="140" alt="Free Mac Cleaner">
</p>

<h1 align="center">Free Mac Cleaner + Video Compress</h1>

<p align="center">
  Libere espaço no Mac de graça: limpe temporários e caches, tire downloads do iCloud sem apagar nada da nuvem e comprima vídeos para HEVC na mesma resolução.
</p>

<p align="center">
  <a href="#-doe">❤️ Doe</a> ·
  <a href="#instalar">Instalar</a> ·
  <a href="#o-que-ele-faz">Recursos</a>
</p>

---

## O que ele faz

**Limpeza (tudo vai para a Lixeira, dá para desfazer)**
- Arquivos temporários, caches de apps, logs
- Xcode e simuladores, caches de ferramentas (npm, pip, Homebrew…)
- Downloads antigos, arquivos grandes e arquivos esquecidos (não abertos há muito tempo)
- Lixeira do Mac e de discos externos
- Temporários em SSD/HD externos (`.Trashes`, `._*` órfãos, `.TemporaryItems`…)
- **Tudo:** uma tela com tudo do Mac + iCloud, com “Selecionar tudo” e um botão geral de limpeza
- **Discos:** cada SSD/HD externo é escaneado separadamente

**iCloud: remover download**
- Remove só a cópia local dos arquivos do iCloud Drive, **sem apagar da nuvem**, em massa
- Ignora arquivos que ainda estão subindo ou com conflito, e protege pastas que você escolher

**Comprimir vídeos**
- Converte `.mp4`/`.mov`/`.m4v` grandes para **HEVC (H.265)** na **mesma resolução**, normalmente com metade do tamanho
- Mantém HDR, áudio, metadados e datas do arquivo
- Usa o chip de vídeo do Mac (Apple Silicon); **Modo rápido** ~35% mais veloz
- Lista por pasta, com status de cada vídeo (na fila, %, OK com o novo tamanho)
- Vídeos já compactos: níveis **Leve** (~25% menor) ou **Forte** (~50% menor), avisando a perda de qualidade
- **Comprimir e manter original** ou **Comprimir e substituir** (original para a Lixeira ou apagado assim que cada vídeo fica pronto)
- Cada vídeo é conferido (duração e tamanho) antes de mexer no original

## Instalar

Requisitos: macOS 15 ou mais novo e as Command Line Tools (`xcode-select --install`). Não precisa do Xcode.

```bash
git clone https://github.com/ZoeDrewLabs/free-mac-cleaner.git
cd free-mac-cleaner
./build-app.sh
cp -R "dist/Free Mac Cleaner + Video Compress.app" /Applications/
```

Na primeira vez, clique com o botão direito no app → **Abrir** (o app é assinado localmente, sem notarização).

Para limpar a Lixeira de discos externos, dê **Acesso Total ao Disco** em Ajustes do Sistema → Privacidade e Segurança.

## ❤️ Doe

O app é grátis e de código aberto. Se ele te ajudou, considere apoiar o projeto:

| | |
|---|---|
| **Pix (CNPJ)** | `54.913.468/0001-04` |
| **LivePix** | [livepix.gg/zoedrewerro404](https://livepix.gg/zoedrewerro404) |

O botão **Doar** também fica dentro do app, na barra lateral e na tela inicial.

## Segurança

- Nada é apagado direto: a limpeza manda para a Lixeira; o iCloud só remove o download local.
- Apagar de vez só acontece quando você escolhe explicitamente (Lixeira ou “substituir e apagar” vídeos).
- Caches usados pelo iCloud e pelo sistema ficam protegidos.

## Licença

[MIT](LICENSE)
