# Notas para a revisão da Apple

Texto para o campo "Notes" da revisão no App Store Connect. Em inglês, porque a revisão o lê assim.

```text
Mural is a local board app (cards, folders, notes) that can share a board through iCloud. The interface is in
Brazilian Portuguese; menu and button names are given below as they appear. Testing sharing needs two Macs (or
two macOS user accounts) signed in to two different Apple Accounts with iCloud Drive on.

Sharing a board (CloudKit):
1. On Mac A, create a board ("Arquivo" > "Novo Mural...") and add a card (paste any text with Command-V and
   press Return).
2. Click the Share button in the window toolbar (or "Arquivo" > "Compartilhar..."), then "Convidar pessoas...".
3. Send the invitation to the Apple Account used on Mac B and let that person make changes.
4. On Mac B, open the link. The board opens in Mural; edits on either Mac appear on the other within seconds.

Live Share (SharePlay):
1. With the board shared as above, start a FaceTime call between the two accounts.
2. On Mac A, open the Share popover and click "Live Share...".
3. Both people see each other's pointer, dragged cards and open card on the board. People in the call who were
   not invited to the board see nothing from it and can ask the owner for access.

iCloud Drive copies:
- Boards created on the account appear as .mural packages in the "Mural" folder of iCloud Drive. This can be
  turned off in "Mural" > "Ajustes..." > "Geral" ("Guardar cópias no iCloud Drive"). Boards received from
  other people are not copied.

No account, login or server of our own is used; all data stays in the user's iCloud.
```

Antes de enviar: publicar o esquema do iCloud em produção (README, "Murais compartilhados pelo iCloud").
