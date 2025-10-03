# Integração do LCD (PCF8574T) com Sensor BMP280 via I2C

* **Nome:** Felipe Marinho

## Descriçãocdo Projeto

Este projeto aborda a comunicação com um display LCD, através de um expansor de portas I2C PCF8574T, e um sensor de pressão e temperatura BMP280.

### O que foi feito:

* **Módulo LCD com PCF8574T:** Foi desenvolvido um mestre I2C simples, focado apenas em operações de escrita, para inicializar o display LCD e exibir uma string de texto.
* **Módulo BMP280:** Foi desenvolvido um mestre I2C completo, capaz de endereçar registradores internos para realizar operações de escrita e leitura. Este módulo inicializa o sensor e realiza a leitura contínua dos dados de temperatura e pressão.

### O que não foi feito:

A integração completa dos dois módulos em um único barramento I2C com um único mestre não foi implementada. O mestre simples do LCD não era suficiente para a comunicação com o BMP280 e o controle multi-mestre do barramento não foi desenvolvido.



