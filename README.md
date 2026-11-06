# Mac Mouse Desk

Aplicativo local para mouses com rodinha lateral e botões extras: **mapeamento de botões e gestos** (clique, duplo clique, segurar e arrastar), **troca de mesas** pela rodinha lateral ou arrastando um botão, **rolagem suave** com velocidades vertical e horizontal separadas e rolagem natural própria. Interface em português, inglês ou espanhol, conforme o idioma do sistema. Sem conta, servidor, assinatura ou telemetria.

Desenvolvido para Apple Silicon e macOS 27.0.1. O código compila com SDK 27 e deployment target macOS 14; versões anteriores não foram validadas fisicamente. Usa APIs privadas do macOS, portanto atualizações do sistema podem exigir ajustes.

## Instalar

Com [Homebrew](https://brew.sh):

```sh
brew trust luishscosta/tap
brew install luishscosta/tap/mac-mouse-desk
```

O Homebrew só carrega receitas de taps de terceiros depois do `brew trust`. A receita fica em [luishscosta/homebrew-tap](https://github.com/luishscosta/homebrew-tap).

Ou baixe `MacMouseDesk.dmg` da [página de versões](https://github.com/luishscosta/mac-mouse-desk/releases/latest), abra e arraste **Mac Mouse Desk** para **Applications** (também há `MacMouseDesk.zip`).

O app tem assinatura ad-hoc e **não é notarizado** pela Apple, então na primeira abertura o macOS o bloqueia como desenvolvedor não identificado. Abra Ajustes do Sistema → Privacidade e Segurança e clique em **Abrir Mesmo Assim** (no aviso, clique em **OK**, não em **Mover para o Lixo**). Outra forma é remover a quarentena do app antes de abrir: `xattr -dr com.apple.quarantine "/Applications/Mac Mouse Desk.app"`. Depois autorize o app em Acessibilidade (veja [Mouse](#mouse)). A partir da 0.1.3 as versões são assinadas com o mesmo certificado, então a autorização de Acessibilidade continua valendo nas atualizações. Quem vem da 0.1.2 ou anterior precisa autorizar uma última vez: remova a entrada antiga com "–" e use **Autorizar…** no app.

Requer Mac com Apple Silicon e macOS 14 ou posterior.

## Compilar e abrir

Com Command Line Tools instalado:

```sh
bash scripts/test.sh
bash scripts/build.sh
mkdir -p ~/Applications
ditto -x -k dist/MacMouseDesk.zip ~/Applications
open ~/Applications/"Mac Mouse Desk.app"
```

O build gera `dist/MacMouseDesk.zip`, contendo o app com assinatura ad-hoc para uso local, e mantém uma cópia executável na pasta temporária informada ao terminar. Não há download de dependências. Instale em `~/Applications` ou `/Applications` **antes** de conceder permissões e registrar o início automático. Evite executar dentro de pasta sincronizada: o File Provider pode acrescentar metadados que invalidam a assinatura. Feche outra cópia do Mac Mouse Desk antes de recompilar/atualizar. Recompilar ou mover o app pode exigir nova autorização do macOS. Não desative SIP ou Gatekeeper.

Para diagnóstico sem capturar entrada nem enviar gestos:

```sh
~/Applications/"Mac Mouse Desk.app"/Contents/MacOS/Mesa --diagnose
```

Um terminal isolado/sandbox pode não enxergar a sessão gráfica ou todos os serviços HID. O app aberto pelo Finder usa a sessão gráfica normal.

## Mouse

1. Conecte o mouse (Bluetooth, cabo ou receptor). O Mac Mouse Desk não filtra por marca: qualquer mouse com roda funciona. Trackpad e mouses de superfície por toque ficam de fora porque rolam com fases de gesto, e eventos criados por outros apps nunca são alterados. O app do fabricante (A HUB, UGREEN etc.) não é necessário.
2. Em **Ajustes**, use **Abrir Acessibilidade** e autorize **Mac Mouse Desk** em Ajustes do Sistema → Privacidade e Segurança → **Acessibilidade** (no macOS 27: **Controle do Dispositivo e Acesso a Dados**). O filtro ativo de rolagem exige essa autorização; Monitoração de Entrada não é um requisito adicional desse caminho. O app não registra teclas nem envia dados. Se o macOS pedir, encerre e reabra o app. O botão **Monitoração de Entrada (opcional)** apenas abre a página alternativa, sem bloquear a ativação.
3. Se o app do fabricante estiver instalado, deixe a rodinha lateral como rolagem horizontal e os botões laterais sem atalhos. Pause outros remapeadores de mouse.
4. Ligue **Ativo** no topo da janela; a escolha fica salva entre aberturas. Na aba **Rolagem**, ajuste **Velocidade vertical** (padrão 10%) e escolha **Rolagem natural** só para o mouse (começa igual ao ajuste do sistema).
5. Teste com pelo menos duas mesas: gire devagar, solte a roda no meio, reverta a direção e faça um giro longo. A animação deve seguir o giro e terminar sem ficar presa.

## Botões e gestos

Na aba **Botões**, escolha um controle no desenho (lateral da frente, lateral de trás, botão do meio ou botão acima da roda) e defina a ação de cada gesto: **Clique**, **Duplo clique**, **Segurar** (0,45 s) e **Arrastar**. Ações: padrão do mouse, Voltar (⌘[), Avançar (⌘]), atalho gravado, Mission Control, Mostrar Mesa, Trocar Mesas (só em Arrastar) ou nenhuma ação. O perfil é global e começa com as duas laterais trocando de mesa ao arrastar, mantendo o clique original.

- Gestos deixados em **Padrão do mouse** repetem o evento original: um clique simples sem mudança chega aos apps como antes; arrastar ou segurar sem ação liberam o botão nativo.
- Com duplo clique configurado, o clique simples espera 0,3 s para diferenciar os dois.
- Ao arrastar para trocar de mesa, o ponteiro fica parado como num gesto do trackpad. Cerca de 400 pontos de movimento horizontal equivalem a uma mesa.
- **Identificar botão** registra o próximo botão pressionado no mouse. O botão acima da roda não tem número fixo: se nada acontecer ao pressioná-lo, o firmware trata esse botão sozinho (como o botão de DPI de alguns mouses) e o macOS não recebe o evento.
- Alguns mouses enviam um atalho de teclado em vez de um clique (por exemplo, o botão do meio envia ⌘Espaço). Para personalizar um botão assim, ative o Mac Mouse Desk em **Monitoração de Entrada**, selecione o controle no desenho, use **Identificar botão** e pressione-o. Só o atalho que vem do mouse é capturado; o mesmo atalho no teclado continua normal.
- Botões esquerdo e direito, outros mouses e o trackpad nunca são alterados.

Os eventos de botões são registrados no log do sistema (`log stream --predicate 'subsystem == "local.macos-config.Mesa"'`) para diagnóstico.

## Execução e idioma

Na aba **Ajustes**: **Rodar em segundo plano** mantém o Mac Mouse Desk ativo ao fechar a janela (desligado, fechar a janela encerra o app e libera o mouse); **Mostrar ícone na barra de menus** controla o ícone com abrir ajustes, pausar mouse e sair; sem o ícone, abrir o app de novo pelo Finder mostra a janela da cópia em execução. **Abrir ao iniciar sessão** usa os Itens de Início de Sessão do macOS.

O idioma segue Ajustes do Sistema › Geral › Idioma e Região (português, inglês ou espanhol; outros idiomas usam inglês). O seletor **Idioma do app** força um deles e vale depois de reabrir o app. As traduções ficam em `Resources/*.lproj/Localizable.strings`, com o texto em português como chave; `scripts/test.sh` falha se faltar tradução.

Na rodinha lateral, **Uma mesa por giro** completa a troca a cada giro; desligado, vale **Passos por mesa**. Segurando a tecla escolhida (⌥ por padrão) a rodinha rola na horizontal com a **Velocidade horizontal** (padrão 10%), sem trocar de mesa.

Rolagem de outros dispositivos com fases (trackpad, mouses de superfície por toque), momentum e eventos sintéticos passam sem alteração. APIs indisponíveis ou falhas detectadas pausam a captura; após repouso ou recuperação da permissão, ela volta sozinha se **Ativo** estiver ligado.

## Início automático e remoção

Em **Ajustes**, ligue **Abrir ao iniciar sessão**. Se o sistema pedir aprovação, use Geral → Itens de Início de Sessão. O início automático abre o app; a captura segue o interruptor **Ativo**.

Para remover: desligue o início automático, saia do Mac Mouse Desk, remova o app pelo Finder e revogue suas entradas em Acessibilidade/Monitoramento de Entrada. Opcionalmente remova preferências com `defaults delete local.macos-config.Mesa` após sair do app. Nenhum driver ou extensão de kernel é instalado.

## Testes e validação física

`scripts/test.sh` executa as mesmas verificações de comportamento usando asserts, sem exigir Xcode completo. As suítes XCTest também estão em `Tests`; para `swift test`, selecione uma instalação de Xcode que inclua XCTest.

Cobertura automatizada: reconhecimento de clique, duplo clique, segurar e arrastar (incluindo retorno ao botão nativo), perfil de botões, rolagem natural, suavização, reversão, encadeamento, término/cancelamento, filtragem e limites do mouse. Os testes não enviam gestos.

Critérios manuais: rodinha lenta/rápida/reversa, bordas das mesas, tela cheia, rolagem vertical e trackpad intactos, suspensão e permissões revogadas. A disponibilidade de símbolos privados e a compilação **não provam** a aceitação do gesto pelo Dock nem a fluidez no hardware.

## Código e licenças

- `Sources/MesaApp`: interface SwiftUI (Órbita), menu, segundo plano e início automático.
- `Resources/*.lproj`: traduções en/es (pt-BR é o idioma de origem).
- `Sources/MouseKit` e `Sources/MouseBridge`: filtragem de mouses com roda, gestos de botões, suavização e gestos do Dock.

Distribuído sob a [licença MIT](LICENSE). A licença acompanha o app compilado em `Contents/Resources`. Para contribuir, veja [CONTRIBUTING.md](CONTRIBUTING.md).
