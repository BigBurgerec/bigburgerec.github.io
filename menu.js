/* Carta de Big Burger (generado desde clientes/big-burger/cliente.json). Precios en centavos. desc = null → ingredientes sin confirmar. */
window.MENU = {
  "categorias": [
    {
      "id": "clasicas",
      "antes": "Pan tradicional",
      "nombre": "Clásicas",
      "extras": true,
      "items": [
        {
          "id": "clasica",
          "nombre": "La clásica",
          "precio": 250,
          "lema": null,
          "desc": "Pan tradicional, carne 140 g, lechuga, tomate y salsa de la casa"
        },
        {
          "id": "cheddar",
          "nombre": "La cheddar",
          "precio": 300,
          "lema": null,
          "desc": "Pan tradicional, carne 140 g, queso cheddar, lechuga, tomate y salsa de la casa"
        },
        {
          "id": "bacon",
          "nombre": "La bacon",
          "precio": 350,
          "lema": null,
          "desc": "Pan tradicional, carne 140 g, tocino, lechuga, tomate y salsa de la casa"
        },
        {
          "id": "bacon-cheese",
          "nombre": "Bacon Cheese",
          "precio": 400,
          "lema": null,
          "desc": "Pan tradicional, carne 140 g, queso cheddar, tocino, lechuga, tomate y salsa de la casa"
        }
      ],
      "corte": "assets/corte-clasicas.webp",
      "corte_alt": "Hamburguesa clásica con tocino, queso cheddar, tomate y lechuga"
    },
    {
      "id": "premium",
      "antes": "Pan de papa artesanal",
      "nombre": "Premium",
      "extras": true,
      "items": [
        {
          "id": "americana",
          "nombre": "Americana",
          "precio": 450,
          "lema": null,
          "desc": "Pan de papa artesanal, carne 140 g, queso cheddar, vegetales, cebolla caramelizada y salsa de la casa"
        },
        {
          "id": "hawaiian-bbq",
          "nombre": "Hawaiian BBQ",
          "precio": 500,
          "lema": null,
          "desc": "Pan de papa artesanal, carne 140 g, queso cheddar, tocino, jamón, piña a la plancha, vegetales y salsa de la casa"
        },
        {
          "id": "doble-americana",
          "nombre": "Doble americana",
          "precio": 550,
          "lema": null,
          "desc": "Pan de papa artesanal, doble carne 140 g, doble queso cheddar, tocino y salsa de la casa"
        }
      ],
      "corte": "assets/corte-premium.webp",
      "corte_alt": "Hamburguesa en pan de papa con tocino, queso cheddar y cebolla morada"
    },
    {
      "id": "insignia",
      "antes": "Pan de papa artesanal",
      "nombre": "Insignia",
      "extras": true,
      "items": [
        {
          "id": "big-mapple",
          "nombre": "Big Mapple Burger",
          "precio": 600,
          "lema": "Pan de papa artesanal",
          "desc": "Pan de papa artesanal, carne 140 g, tocino, queso, queso labneh, miel maple y salsa de la casa"
        },
        {
          "id": "tocino-lovers",
          "nombre": "Tocino Lovers",
          "precio": 700,
          "lema": "Pan de papa artesanal",
          "desc": "Pan de papa artesanal, carne 140 g, doble queso, 4 tiras de tocino, cebolla caramelizada y salsa de la casa"
        },
        {
          "id": "portobello",
          "nombre": "Portobello",
          "precio": 750,
          "lema": "Pan de papa artesanal",
          "desc": "Pan de papa artesanal, carne 140 g, queso, tocino, queso labneh, champiñones portobello y salsa de la casa"
        }
      ]
    },
    {
      "id": "bebidas",
      "antes": "Para tomar",
      "nombre": "Bebidas",
      "extras": false,
      "items": [
        {
          "id": "bebida-gaseosa",
          "nombre": "Gaseosa personal",
          "precio": 100,
          "lema": null,
          "desc": null
        },
        {
          "id": "bebida-agua",
          "nombre": "Agua sin gas",
          "precio": 75,
          "lema": null,
          "desc": null
        },
        {
          "id": "bebida-jugo",
          "nombre": "Jugo natural",
          "precio": 150,
          "lema": null,
          "desc": null
        }
      ]
    }
  ],
  "extras": [
    {
      "id": "x-carne",
      "nombre": "Carne extra 140 g",
      "precio": 150
    },
    {
      "id": "x-queso",
      "nombre": "Queso cheddar extra",
      "precio": 50
    },
    {
      "id": "x-tocino",
      "nombre": "Tocino extra",
      "precio": 75
    }
  ],
  "temporada": null,
  "sugerir": {
    "categoria": "bebidas",
    "titulo": "¿Le sumas una bebida?"
  }
};
