package com.ninodebolso.app

import android.app.Activity
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Pick what Nino is (sprout, baby or little human) and dress it up. Changes apply right away. */
class WardrobeActivity : Activity() {
    private lateinit var p: Pal
    private lateinit var preview: PetView
    private lateinit var options: LinearLayout
    private var look = Store.look

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        p = pal(this)
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(8), dp(16), dp(32))
        }
        val scroll = ScrollView(this).apply {
            setBackgroundColor(p.bg)
            addView(col)
        }

        val head = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        head.addView(TextView(this).apply {
            text = "Visual do ${Store.petName}"
            setTextColor(p.ink); textSize = 24f; typeface = Typeface.DEFAULT_BOLD
        }, LinearLayout.LayoutParams(0, -2, 1f))
        head.addView(pill("Pronto", true) { finish() })
        col.addView(head)

        val stage = FrameLayout(this).apply {
            background = rounded(p.surface, dpf(24))
            setPadding(0, dp(10), 0, dp(6))
        }
        preview = PetView(this)
        preview.look = look
        preview.level = Store.level()
        preview.setOnClickListener { preview.hearts(3); preview.express("carinhoso", 2000); preview.wave() }
        stage.addView(preview, FrameLayout.LayoutParams(dp(190), dp(202), Gravity.CENTER_HORIZONTAL))
        col.addView(stage, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(pill("Aleatório", false) { apply(Look.random()) }, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(pill("Voltar ao original", false) { apply(Look()) }, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(8) })
        col.addView(row, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(10) })

        options = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        col.addView(options)
        buildOptions()
        setContentView(scroll)
        edgeToEdge(scroll)
    }

    override fun onResume() {
        super.onResume()
        PetService.instance?.setOverlayVisible(false)
    }

    override fun onPause() {
        PetService.instance?.setOverlayVisible(true)
        super.onPause()
    }

    private fun apply(l: Look) {
        look = l
        Store.look = l
        Store.changed()
        preview.look = l
        preview.express(listOf("animado", "carinhoso", "brincalhao").random(), 1800)
        preview.sparkles()
        buildOptions()
    }

    private fun pill(text: String, primary: Boolean, onClick: () -> Unit) = TextView(this).apply {
        this.text = text
        gravity = Gravity.CENTER
        textSize = 15f
        typeface = Typeface.DEFAULT_BOLD
        setPadding(dp(16), dp(10), dp(16), dp(10))
        setTextColor(if (primary) p.accentInk else p.accent)
        background = rounded(if (primary) p.accent else p.accentSoft, dpf(14))
        setOnClickListener { onClick() }
    }

    private fun section(title: String): LinearLayout {
        val c = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(14))
            background = rounded(p.surface, dpf(20))
        }
        c.addView(TextView(this).apply {
            text = title.uppercase()
            setTextColor(p.muted); textSize = 11.5f; letterSpacing = 0.08f; typeface = Typeface.DEFAULT_BOLD
        })
        options.addView(c, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
        return c
    }

    private fun chips(parent: LinearLayout, items: Map<String, String>, selected: String, onPick: (String) -> Unit) {
        val flow = FlowLayout(this)
        items.forEach { (id, label) ->
            val on = id == selected
            flow.addView(TextView(this).apply {
                text = label
                textSize = 14f
                setPadding(dp(14), dp(8), dp(14), dp(8))
                setTextColor(if (on) p.accentInk else p.ink)
                typeface = if (on) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                background = rounded(if (on) p.accent else p.surface2, dpf(99), if (on) p.accent else p.line, dp(1))
                setOnClickListener { onPick(id) }
            })
        }
        parent.addView(flow, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
    }

    private fun swatches(parent: LinearLayout, tones: List<Tone>, selected: Int, onPick: (Int) -> Unit) {
        val flow = FlowLayout(this)
        tones.forEachIndexed { i, t ->
            val on = i == selected
            flow.addView(View(this).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    colors = intArrayOf(t.hi, t.base)
                    setStroke(if (on) dp(4) else dp(1), if (on) p.accent else p.line)
                }
                contentDescription = t.name
                layoutParams = android.view.ViewGroup.LayoutParams(dp(40), dp(40))
                setOnClickListener { onPick(i) }
            })
        }
        parent.addView(flow, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(10) })
    }

    private fun buildOptions() {
        options.removeAllViews()
        val l = look
        val human = l.species != "broto"

        chips(section("Quem é ele"), Looks.SPECIES, l.species) { sp ->
            apply(l.copy(species = sp, color = 0, hair = if (sp == "bebe" && l.hair == "nenhum") "cachinho" else if (sp == "humano" && l.hair == "nenhum") "curto" else l.hair))
        }
        swatches(section(if (human) "Tom de pele" else "Cor"), if (human) Looks.SKIN else Looks.BODY, l.color) { apply(l.copy(color = it)) }
        if (human) {
            val hair = section("Cabelo")
            chips(hair, Looks.HAIR_STYLES, l.hair) { apply(l.copy(hair = it)) }
            if (l.hair != "nenhum") swatches(hair, Looks.HAIR, l.hairColor) { apply(l.copy(hairColor = it)) }
            swatches(section("Cor da roupa"), Looks.CLOTH, l.outfit) { apply(l.copy(outfit = it)) }
        }
        val hat = section("Chapéu")
        chips(hat, Looks.HATS, l.hat) { apply(l.copy(hat = it)) }
        chips(section("Óculos"), Looks.GLASSES, l.glasses) { apply(l.copy(glasses = it)) }
        chips(section("Extra"), Looks.EXTRAS, l.extra) { apply(l.copy(extra = it)) }
        val usesAccent = (l.hat != "nenhum" && l.hat != "coroa") || l.extra == "cachecol" || l.extra == "gravata" || l.hair == "chiquinhas"
        if (usesAccent) swatches(section("Cor do chapéu e dos acessórios"), Looks.CLOTH, l.hatColor) { apply(l.copy(hatColor = it)) }
    }
}
