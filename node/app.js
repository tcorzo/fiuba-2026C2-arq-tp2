import express from 'express';
import axios from 'axios';
import config from './config.js'

const app = express();

app.get('/', (req, res) => {
    res.status(200).send('Server is up.')
});

app.get('/:dni', async (req, res) => {
    try {
        const response = await axios.post(`${config.arcaUri}/validar`, {dni: parseInt(req.params.dni)});
        if (response.status == 200) {
            res.status(200).send(response.data);
        } else {
            res.status(500).send(`Unexpected return code ${response.status} from ARCA`);
        }
    } catch (e) {
        console.error("Exception consuming ARCA's service", e);
        res.status(500).send("Exception consuming ARCA's service");
    }
})

app.listen(3000, () => console.log("Listening on port 3000"));