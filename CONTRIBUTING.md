# Contribuindo

Obrigado pelo interesse no Mac Mouse Desk. Issues e pull requests são bem-vindos em português, inglês ou espanhol.

## Reportar um problema

Abra uma issue com:

- versão do macOS e do Mac Mouse Desk (Ajustes → sobre, ou `CFBundleShortVersionString`);
- modelo do mouse e como está conectado (Bluetooth, receptor, cabo);
- o que esperava e o que aconteceu, com passos para reproduzir;
- a saída de `~/Applications/"Mac Mouse Desk.app"/Contents/MacOS/Mesa --diagnose` e, se for sobre botões, o log de `log stream --predicate 'subsystem == "local.macos-config.Mesa"'`.

Confira antes se outro remapeador de mouse está ativo: eles disputam os mesmos eventos.

## Enviar uma mudança

1. Faça um fork e crie um branch a partir de `main` (`feat/…`, `fix/…`, `docs/…`).
2. Compile e teste com Command Line Tools:

   ```sh
   bash scripts/test.sh
   bash scripts/build.sh
   ```

   Sem certificado, o build usa assinatura ad-hoc e o macOS pede a autorização de Acessibilidade a cada build. Para evitar isso no seu Mac, crie em Acesso às Chaves um certificado de assinatura de código autoassinado e passe o nome dele em `MMD_SIGN_IDENTITY`. As versões publicadas são assinadas com o certificado "Mac Mouse Desk Self-Signed" do mantenedor.

   `scripts/test.sh` precisa passar: ele roda as verificações de comportamento, valida os plists e exige tradução em inglês e espanhol para todo texto novo.
3. Textos da interface usam `L("texto em português")`. Adicione a mesma chave em `Resources/en.lproj/Localizable.strings` e `Resources/es.lproj/Localizable.strings`.
4. Teste no hardware o que mudou (troca de mesas, gestos, trackpad intacto) e descreva o teste no pull request.
5. Use mensagens de commit no formato [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`…).

Mantenha as mudanças pequenas e focadas. O app não deve ganhar telemetria, conta, servidor nem dependências externas.

## Licença

Ao contribuir, você concorda que sua contribuição seja licenciada sob a [licença MIT](LICENSE) do projeto.
