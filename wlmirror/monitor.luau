-- monitor.luau
-- Revisa cada 2s si wl-mirror sigue vivo (por si el usuario lo cerró
-- manualmente con la ventana) y publica el estado para el shortcut.

noctalia.setUpdateInterval(2000)

function update()
  noctalia.processMatches(function(matched)
    noctalia.state.set("running", matched)
  end, "wl-mirror")
end
