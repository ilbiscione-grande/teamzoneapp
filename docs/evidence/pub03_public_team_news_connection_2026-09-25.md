# Nyheternas koppling till publika lagsidor

Produktägaren upplevde att kopplingen saknades. Skrivskyddad kontroll i
`hgcshgunvooyudvrcpig` visade att `testrubriken` var published med klubbkanal,
Thomas lag som vald lagkanal, innehållsprojektion och en publik lagkoppling.
Extern HTTP-hämtning av Thomas lags sida gav 200 och innehöll rubriken.

Den redan öppna browserfliken hade äldre sidinnehåll utan nyheten. Navigering
till samma sidas #nyheter ändrade bara ankaret. Efter riktig omladdning syntes
`testrubriken`, ingressen och länken `/thomas-klubb-6379829a/nyheter/testrubrik`.
Ingen databasändring eller ompublicering av användarens nyhet behövdes.

Lokala appetiketter har förtydligats: klubbens publika sida respektive lagets
publika sida och följarnas flöde. Nyhetslistan visar också valda lags namn,
och förhandsgranskningen förklarar vilka publika sidor nyheten ska visas på.
Den här etikettändringen distribueras inte automatiskt till externa Flutter-
installationer.
