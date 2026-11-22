package com.ninodebolso.app

import org.json.JSONObject

/** One color with its lighter highlight, darker shade and outline. */
class Tone(val name: String, val hi: Int, val base: Int, val shade: Int, val line: Int)

private fun tone(name: String, hi: Long, base: Long, shade: Long, line: Long) =
    Tone(name, hi.toInt(), base.toInt(), shade.toInt(), line.toInt())

/** How the pet looks. Every field is an id or a palette index, so it saves as plain JSON. */
data class Look(
    val species: String = "broto",
    val color: Int = 0,
    val hair: String = "nenhum",
    val hairColor: Int = 1,
    val hat: String = "nenhum",
    val hatColor: Int = 1,
    val glasses: String = "nenhum",
    val outfit: Int = 0,
    val extra: String = "nenhum",
) {
    fun toJson(): JSONObject = JSONObject()
        .put("species", species).put("color", color).put("hair", hair).put("hairColor", hairColor)
        .put("hat", hat).put("hatColor", hatColor).put("glasses", glasses).put("outfit", outfit).put("extra", extra)

    fun body(): Tone = if (species == "broto") Looks.BODY.getOrElse(color) { Looks.BODY[0] } else Looks.SKIN.getOrElse(color) { Looks.SKIN[0] }
    fun hairTone(): Tone = Looks.HAIR.getOrElse(hairColor) { Looks.HAIR[1] }
    fun hatTone(): Tone = Looks.CLOTH.getOrElse(hatColor) { Looks.CLOTH[1] }
    fun outfitTone(): Tone = Looks.CLOTH.getOrElse(outfit) { Looks.CLOTH[0] }

    /** A short description in Portuguese, for the AI to know what it looks like. */
    fun describe(): String {
        val parts = mutableListOf<String>()
        when (species) {
            "bebe" -> parts += "um bebezinho fofo de macacão na cor ${outfitTone().name}"
            "humano" -> parts += "um humaninho pequenininho, de roupa na cor ${outfitTone().name}"
            else -> parts += "um broto ${body().name}, redondo e gordinho, com uma folhinha na cabeça"
        }
        if (species != "broto") parts += "pele ${body().name}"
        if (species != "broto" && hair != "nenhum") parts += "cabelo ${(Looks.HAIR_STYLES[hair] ?: hair).lowercase()} ${hairTone().name}"
        if (hat == "coroa") parts += "uma coroa dourada"
        else if (hat != "nenhum") parts += "${(Looks.HATS[hat] ?: hat).lowercase()} na cor ${hatTone().name}"
        if (glasses != "nenhum") parts += "óculos ${(Looks.GLASSES[glasses] ?: glasses).lowercase()}"
        if (extra != "nenhum") parts += (Looks.EXTRAS[extra] ?: extra).lowercase()
        return parts.joinToString(", ")
    }

    companion object {
        fun from(o: JSONObject?): Look {
            if (o == null) return Look()
            val d = Look()
            return Look(
                o.optString("species", d.species).let { if (it in Looks.SPECIES) it else d.species },
                o.optInt("color", d.color),
                o.optString("hair", d.hair).let { if (it in Looks.HAIR_STYLES) it else d.hair },
                o.optInt("hairColor", d.hairColor),
                o.optString("hat", d.hat).let { if (it in Looks.HATS) it else d.hat },
                o.optInt("hatColor", d.hatColor),
                o.optString("glasses", d.glasses).let { if (it in Looks.GLASSES) it else d.glasses },
                o.optInt("outfit", d.outfit),
                o.optString("extra", d.extra).let { if (it in Looks.EXTRAS) it else d.extra },
            )
        }

        fun random(): Look {
            val sp = Looks.SPECIES.keys.random()
            return Look(
                species = sp,
                color = (if (sp == "broto") Looks.BODY.indices else Looks.SKIN.indices).random(),
                hair = if (sp == "broto") "nenhum" else Looks.HAIR_STYLES.keys.random(),
                hairColor = Looks.HAIR.indices.random(),
                hat = if (Math.random() < 0.6) Looks.HATS.keys.random() else "nenhum",
                hatColor = Looks.CLOTH.indices.random(),
                glasses = if (Math.random() < 0.35) Looks.GLASSES.keys.random() else "nenhum",
                outfit = Looks.CLOTH.indices.random(),
                extra = if (Math.random() < 0.4) Looks.EXTRAS.keys.filter { sp == "bebe" || it != "chupeta" }.random() else "nenhum",
            )
        }
    }
}

object Looks {
    val SPECIES = linkedMapOf("broto" to "Broto", "bebe" to "Bebê", "humano" to "Humaninho")

    val BODY = listOf(
        tone("amarelinho", 0xFFFFEBA6, 0xFFFFC845, 0xFFF29A2E, 0xE6C9741F),
        tone("verdinho", 0xFFDDF7C4, 0xFF8BD46A, 0xFF4FA83A, 0xE63F8A2C),
        tone("rosinha", 0xFFFFE3EF, 0xFFFF9EC4, 0xFFE5679B, 0xE6C24F80),
        tone("azulzinho", 0xFFDDF0FF, 0xFF7CC4FF, 0xFF3F8FE0, 0xE6346FB0),
        tone("roxinho", 0xFFEDE5FF, 0xFFB99BFF, 0xFF7F5FE0, 0xE66749B8),
        tone("laranjinha", 0xFFFFDDC2, 0xFFFFA25C, 0xFFE06A1F, 0xE6B8561A),
    )

    val SKIN = listOf(
        tone("clara", 0xFFFFF3E8, 0xFFFFDDC4, 0xFFEFBF9C, 0xE6C08A66),
        tone("clara rosada", 0xFFFFEDE0, 0xFFF6C9A6, 0xFFE0A47D, 0xE6B07A55),
        tone("morena clara", 0xFFF6D3AE, 0xFFDDA574, 0xFFC0844F, 0xE6945F35),
        tone("morena", 0xFFD9A57A, 0xFFB57A4B, 0xFF955C31, 0xE6704222),
        tone("negra", 0xFFB07B55, 0xFF8A5634, 0xFF6C3E21, 0xE6502C16),
        tone("negra retinta", 0xFF835A40, 0xFF5E3A24, 0xFF472A18, 0xE6321C0F),
    )

    val HAIR = listOf(
        tone("preto", 0xFF4A403C, 0xFF2B2422, 0xFF161210, 0xFF0E0B0A),
        tone("castanho", 0xFF9A6A45, 0xFF6B4226, 0xFF4D2E19, 0xFF3A2212),
        tone("loiro", 0xFFFFE89A, 0xFFF2C94C, 0xFFD7A42C, 0xFFB08520),
        tone("ruivo", 0xFFFFA36B, 0xFFD9682B, 0xFFB14E1A, 0xFF8C3C12),
        tone("rosa", 0xFFFFC2DD, 0xFFFF7EB6, 0xFFE0558F, 0xFFB83F72),
        tone("azul", 0xFF9EC2FF, 0xFF4F8BFF, 0xFF2F64D6, 0xFF244DA8),
        tone("roxo", 0xFFC9B8FF, 0xFF8E6CFF, 0xFF6646D6, 0xFF4E33AD),
        tone("branco", 0xFFFFFFFF, 0xFFEDEDED, 0xFFC9C9C9, 0xFF9A9A9A),
    )

    val CLOTH = listOf(
        tone("azul", 0xFF8FA8FF, 0xFF3D6BFF, 0xFF2A4FD1, 0xFF1F3DA3),
        tone("vermelha", 0xFFFF9C9C, 0xFFFF5A5A, 0xFFD93C3C, 0xFFA82C2C),
        tone("verde", 0xFF8EE0B6, 0xFF3FBF7F, 0xFF2C9A63, 0xFF217A4D),
        tone("amarela", 0xFFFFE88A, 0xFFFFD23F, 0xFFE0B21F, 0xFFB08A12),
        tone("rosa", 0xFFFFC4DF, 0xFFFF8AC0, 0xFFE0609E, 0xFFB5477C),
        tone("roxa", 0xFFC6B6FF, 0xFF8B6CFF, 0xFF6A4BE0, 0xFF5036B3),
        tone("preta", 0xFF5A5A6E, 0xFF2E2E3A, 0xFF1C1C25, 0xFF0F0F15),
        tone("branca", 0xFFFFFFFF, 0xFFF5F5F5, 0xFFD9D9DF, 0xFFA6A6B0),
    )

    val HAIR_STYLES = linkedMapOf(
        "nenhum" to "Careca", "curto" to "Curto", "cacheado" to "Cacheado", "longo" to "Longo",
        "chiquinhas" to "Maria-chiquinha", "coque" to "Coque", "moicano" to "Moicano", "afro" to "Black power", "cachinho" to "Cachinho",
    )
    val HATS = linkedMapOf(
        "nenhum" to "Nenhum", "bone" to "Boné", "gorro" to "Gorro", "coroa" to "Coroa", "festa" to "Chapéu de festa",
        "bruxa" to "Chapéu de bruxa", "cartola" to "Cartola", "laco" to "Laço", "palha" to "Chapéu de palha",
    )
    val GLASSES = linkedMapOf("nenhum" to "Nenhum", "redondo" to "Redondo", "escuro" to "Escuro", "coracao" to "Coração")
    val EXTRAS = linkedMapOf("nenhum" to "Nenhum", "chupeta" to "Chupeta", "cachecol" to "Cachecol", "gravata" to "Gravatinha")
}
