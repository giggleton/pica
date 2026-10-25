# Test fonts

Every font here is a full original file, exactly as its project published it, with its licence
beside it. None is subset or edited: Lato, Lobster, Liberation and Source Serif reserve their
names under the SIL Open Font License, so a modified copy could not keep its name. The two built
files, `Roboto-Collection.ttc` and `Roboto-Bare.ttf`, are made from Roboto, whose licence reserves
no name, by `test/support/ground_truth/build_fonts.py`.

Expected values for these fonts come from outside tools, never from Pica
(`test/support/ground_truth/`). When a file here changes, rerun the generators named there and
update its line below.

| File | Version | Source | Licence | SHA-256 |
|---|---|---|---|---|
| `Lato-Regular.ttf` | 2.015 | [google/fonts `ofl/lato` at f3b885d5590e](https://github.com/google/fonts/tree/f3b885d5590e/ofl/lato) | OFL 1.1, Reserved Font Name "Lato" (`Lato-OFL.txt`) | `d636e4683231f931eda222d588e944d082bfd3bdba02f928bee461c0f185b251` |
| `Lato-Bold.ttf` | 2.015 | [google/fonts `ofl/lato` at f3b885d5590e](https://github.com/google/fonts/tree/f3b885d5590e/ofl/lato) | OFL 1.1, Reserved Font Name "Lato" (`Lato-OFL.txt`) | `8a0aace75d33794eece4b28187bfc1df0bbd2888b5d8a56e01788c8d65d16be1` |
| `Lobster-Regular.ttf` | 2.100 | [google/fonts `ofl/lobster` at 98f1d55df3f7](https://github.com/google/fonts/tree/98f1d55df3f7/ofl/lobster) | OFL 1.1, Reserved Font Name "Lobster" (`Lobster-OFL.txt`) | `d6568e697fd50cedc0be04d8aae4127fe95add607e7bff954ca88604be80c205` |
| `Roboto[wdth,wght].ttf` | 3.015 | [google/fonts `ofl/roboto` at 6183fc0d2636](https://github.com/google/fonts/tree/6183fc0d2636/ofl/roboto) | OFL 1.1, no reserved name (`Roboto-OFL.txt`) | `d7598e12c5dbef095ff8272cfc55da0250bd07fbdecbac8a530b9b277872a134` |
| `LiberationSans-Regular.ttf` | 2.1.5 | [liberation-fonts 2.1.5, `liberation-fonts-ttf-2.1.5.tar.gz`](https://github.com/liberationfonts/liberation-fonts/releases/tag/2.1.5) | OFL 1.1, Reserved Font Name "Liberation" (`LiberationSans-LICENSE.txt`) | `76d04c18ea243f426b7de1f3ad208e927008f961dc5945e5aad352d0dfde8ee8` |
| `SourceSerif4-Regular.otf` | 4.005 | [adobe-fonts/source-serif 4.005R, `source-serif-4.005_Desktop.zip`, `OTF/`](https://github.com/adobe-fonts/source-serif/releases/tag/4.005R) | OFL 1.1, Reserved Font Name "Source" (`SourceSerif4-LICENSE.md`) | `edf160d0d584deee8a3bb2c3371b2a7624ca63580fbe02c57c1f4c91e84d8787` |
| `SourceSerif4-Regular.otf.woff2` | 4.005 | [adobe-fonts/source-serif 4.005R, `source-serif-4.005_WOFF2.zip`, `OTF/`](https://github.com/adobe-fonts/source-serif/releases/tag/4.005R) | OFL 1.1, Reserved Font Name "Source" (`SourceSerif4-LICENSE.md`) | `42aa010dbb82d90764a28f6cc7d809a9395999b7390eb3b212028c6975e97402` |
| `SourceSerif4-Regular.ttf.woff` | 4.005 | [adobe-fonts/source-serif 4.005R, `source-serif-4.005_WOFF.zip`, `TTF/`](https://github.com/adobe-fonts/source-serif/releases/tag/4.005R) | OFL 1.1, Reserved Font Name "Source" (`SourceSerif4-LICENSE.md`) | `04ff8c051752c0dca81908fdd17162ce4d2904669be8fb68814c4d36d8e7902d` |
| `Roboto-Collection.ttc` | built | `build_fonts.py`: `Roboto[wdth,wght].ttf` and its bold instance (wght 700, wdth 100), fontTools 4.67.0 | OFL 1.1, as Roboto (`Roboto-OFL.txt`) | `b9774892a456f8a0cbb7d5dbd7e743bd772a0e09bc1c257b2b229edd73097632` |
| `Roboto-Bare.ttf` | built | `build_fonts.py`: `Roboto[wdth,wght].ttf` without its OS/2 table or family names, marked italic in head, fontTools 4.67.0 | OFL 1.1, as Roboto (`Roboto-OFL.txt`) | `84c3cdcb75bced2ddeb89d6c36585f7e09539ad711f51166bc583ffe53b954f0` |
