import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.JSONArray;
import com.alibaba.fastjson.JSONObject;
import com.alibaba.fastjson.serializer.SerializerFeature;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;

public class JsonHandler {

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));

        StringBuilder builder = new StringBuilder();
        while (true) {
            String line = reader.readLine();
            if (line == null) {
                break;
            }
            builder.append(line);
        }
        List<SerializerFeature> features = new ArrayList<>();
        features.add(SerializerFeature.WriteNonStringKeyAsString);

        if (args.length >= 1) {
            if ("-a".equals(args[0])) {
                features.add(SerializerFeature.DisableCircularReferenceDetect);
            }
        }

        Object json = JSON.parse(builder.toString());
        if (json instanceof JSONObject) {
            System.out.println(((JSONObject) json).toString(features.toArray(new SerializerFeature[0])));
        } else if (json instanceof JSONArray) {
            System.out.println(((JSONArray) json).toString(features.toArray(new SerializerFeature[0])));
        }
    }

}
