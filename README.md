# JOMO Keymap

![keymap](./jomo_keymap.svg)

```sh
keymap parse -c 10 -z ./boards/shields/jomo/jomo.keymap > jomo_keymap.yaml
keymap draw -d ./boards/shields/jomo/jomo-layouts.dtsi jomo_keymap.yaml > jomo_keymap.svg
```
